import Foundation

/// Small ZIP reader/writer used for .mcworld packages.
/// Supports stored and raw-deflate entries, UTF-8 names and non-ZIP64 archives.
enum MiniZipArchive {
  private static let localHeaderSignature: UInt32 = 0x0403_4b50
  private static let centralHeaderSignature: UInt32 = 0x0201_4b50
  private static let endSignature: UInt32 = 0x0605_4b50
  private static let maximumSingleEntrySize = Int64(2) * 1_024 * 1_024 * 1_024
  private static let maximumTotalExtractedSize = Int64(64) * 1_024 * 1_024 * 1_024
  private static let maximumSuspiciousExpansionRatio: Int64 = 10_000

  private struct Entry {
    let path: String
    let method: UInt16
    let crc32: UInt32
    let compressedSize: Int
    let uncompressedSize: Int
    let localHeaderOffset: Int
  }

  static func extract(archiveURL: URL, to destination: URL) throws {
    let archive = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
    let entries = try parseCentralDirectory(archive)
    let validatedEntries = try validateForExtraction(entries)
    let manager = FileManager.default
    try manager.createDirectory(at: destination, withIntermediateDirectories: true)
    let destinationPath = destination.standardizedFileURL.path

    for (entry, safeRelative) in validatedEntries {
      if safeRelative.isEmpty { continue }
      let outputURL = destination.appendingPathComponent(safeRelative)
      let outputPath = outputURL.standardizedFileURL.path
      guard outputPath == destinationPath || outputPath.hasPrefix(destinationPath + "/") else {
        throw MCBEEditorError.invalidArchive("路径逃逸：\(entry.path)")
      }
      if entry.path.hasSuffix("/") {
        try manager.createDirectory(at: outputURL, withIntermediateDirectories: true)
        continue
      }

      guard try archive.littleEndianUInt32(at: entry.localHeaderOffset) == localHeaderSignature
      else {
        throw MCBEEditorError.invalidArchive("本地文件头损坏：\(entry.path)")
      }
      let nameLength = Int(try archive.littleEndianUInt16(at: entry.localHeaderOffset + 26))
      let extraLength = Int(try archive.littleEndianUInt16(at: entry.localHeaderOffset + 28))
      let dataOffset = entry.localHeaderOffset + 30 + nameLength + extraLength
      guard dataOffset >= 0, dataOffset + entry.compressedSize <= archive.count else {
        throw MCBEEditorError.invalidArchive("文件数据越界：\(entry.path)")
      }
      let compressed = archive.subdata(in: dataOffset..<(dataOffset + entry.compressedSize))
      let content: Data
      switch entry.method {
      case 0:
        content = compressed
      case 8:
        content = try BTCompressionBridge.inflateRaw(
          compressed, expectedSize: UInt(entry.uncompressedSize))
      default:
        throw MCBEEditorError.unsupported("ZIP 压缩方法 \(entry.method)")
      }
      guard content.count == entry.uncompressedSize else {
        throw MCBEEditorError.invalidArchive("解压后长度不匹配：\(entry.path)")
      }
      guard BTCompressionBridge.crc32(content) == entry.crc32 else {
        throw MCBEEditorError.invalidArchive("CRC 校验失败：\(entry.path)")
      }
      try manager.createDirectory(
        at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try content.write(to: outputURL, options: .atomic)
    }
  }

  static func create(from directory: URL, to archiveURL: URL) throws {
    let manager = FileManager.default
    guard
      let enumerator = manager.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    else {
      throw MCBEEditorError.io("无法枚举 \(directory.path)")
    }

    struct CentralRecord {
      let pathData: Data
      let crc32: UInt32
      let compressedSize: UInt32
      let uncompressedSize: UInt32
      let localOffset: UInt32
      let method: UInt16
      let isDirectory: Bool
    }

    var output = Data()
    var central = [CentralRecord]()
    let rootPath = directory.standardizedFileURL.path

    while let fileURL = enumerator.nextObject() as? URL {
      let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
      let standardized = fileURL.standardizedFileURL.path
      guard standardized.hasPrefix(rootPath + "/") else { continue }
      var relative = String(standardized.dropFirst(rootPath.count + 1)).replacingOccurrences(
        of: "\\", with: "/")
      let isDirectory = values.isDirectory == true
      if isDirectory && !relative.hasSuffix("/") { relative.append("/") }
      guard let pathData = relative.data(using: .utf8), pathData.count <= Int(UInt16.max) else {
        throw MCBEEditorError.io("文件名过长：\(relative)")
      }

      let original = isDirectory ? Data() : try Data(contentsOf: fileURL, options: .mappedIfSafe)
      guard original.count <= Int(UInt32.max) else {
        throw MCBEEditorError.unsupported("单个文件超过 4 GiB：\(relative)")
      }
      let method: UInt16 = isDirectory || original.isEmpty ? 0 : 8
      let compressed =
        method == 8 ? try BTCompressionBridge.deflateRaw(original, level: 6) : original
      guard compressed.count <= Int(UInt32.max), output.count <= Int(UInt32.max) else {
        throw MCBEEditorError.unsupported("ZIP64")
      }
      let crc = BTCompressionBridge.crc32(original)
      let localOffset = UInt32(output.count)

      output.appendLE(localHeaderSignature)
      output.appendLE(UInt16(20))
      output.appendLE(UInt16(0x0800))  // UTF-8
      output.appendLE(method)
      output.appendLE(UInt16(0))
      output.appendLE(UInt16(0))
      output.appendLE(crc)
      output.appendLE(UInt32(compressed.count))
      output.appendLE(UInt32(original.count))
      output.appendLE(UInt16(pathData.count))
      output.appendLE(UInt16(0))
      output.append(pathData)
      output.append(compressed)

      central.append(
        CentralRecord(
          pathData: pathData,
          crc32: crc,
          compressedSize: UInt32(compressed.count),
          uncompressedSize: UInt32(original.count),
          localOffset: localOffset,
          method: method,
          isDirectory: isDirectory
        ))
    }

    guard central.count <= Int(UInt16.max), output.count <= Int(UInt32.max) else {
      throw MCBEEditorError.unsupported("ZIP64")
    }
    let centralOffset = UInt32(output.count)
    for record in central {
      output.appendLE(centralHeaderSignature)
      output.appendLE(UInt16(0x0314))
      output.appendLE(UInt16(20))
      output.appendLE(UInt16(0x0800))
      output.appendLE(record.method)
      output.appendLE(UInt16(0))
      output.appendLE(UInt16(0))
      output.appendLE(record.crc32)
      output.appendLE(record.compressedSize)
      output.appendLE(record.uncompressedSize)
      output.appendLE(UInt16(record.pathData.count))
      output.appendLE(UInt16(0))
      output.appendLE(UInt16(0))
      output.appendLE(UInt16(0))
      output.appendLE(UInt16(0))
      output.appendLE(record.isDirectory ? UInt32(0x10) : UInt32(0))
      output.appendLE(record.localOffset)
      output.append(record.pathData)
    }
    let centralSize = UInt32(output.count) - centralOffset
    output.appendLE(endSignature)
    output.appendLE(UInt16(0))
    output.appendLE(UInt16(0))
    output.appendLE(UInt16(central.count))
    output.appendLE(UInt16(central.count))
    output.appendLE(centralSize)
    output.appendLE(centralOffset)
    output.appendLE(UInt16(0))
    try AtomicFile.write(output, to: archiveURL)
  }

  private static func parseCentralDirectory(_ archive: Data) throws -> [Entry] {
    guard archive.count >= 22 else { throw MCBEEditorError.invalidArchive("文件太短") }
    let minimum = max(0, archive.count - 65_557)
    var endOffset: Int?
    var cursor = archive.count - 22
    while cursor >= minimum {
      if (try? archive.littleEndianUInt32(at: cursor)) == endSignature {
        endOffset = cursor
        break
      }
      cursor -= 1
    }
    guard let eocd = endOffset else { throw MCBEEditorError.invalidArchive("未找到中央目录") }
    let disk = try archive.littleEndianUInt16(at: eocd + 4)
    let centralDisk = try archive.littleEndianUInt16(at: eocd + 6)
    guard disk == 0, centralDisk == 0 else { throw MCBEEditorError.unsupported("分卷 ZIP") }
    let entryCount = Int(try archive.littleEndianUInt16(at: eocd + 10))
    let centralSize = Int(try archive.littleEndianUInt32(at: eocd + 12))
    let centralOffset = Int(try archive.littleEndianUInt32(at: eocd + 16))
    guard centralOffset >= 0, centralOffset + centralSize <= archive.count else {
      throw MCBEEditorError.invalidArchive("中央目录越界")
    }

    var entries = [Entry]()
    entries.reserveCapacity(entryCount)
    var offset = centralOffset
    for _ in 0..<entryCount {
      guard try archive.littleEndianUInt32(at: offset) == centralHeaderSignature else {
        throw MCBEEditorError.invalidArchive("中央目录条目损坏")
      }
      let flags = try archive.littleEndianUInt16(at: offset + 8)
      let method = try archive.littleEndianUInt16(at: offset + 10)
      let crc = try archive.littleEndianUInt32(at: offset + 16)
      let compressedSize = Int(try archive.littleEndianUInt32(at: offset + 20))
      let uncompressedSize = Int(try archive.littleEndianUInt32(at: offset + 24))
      let nameLength = Int(try archive.littleEndianUInt16(at: offset + 28))
      let extraLength = Int(try archive.littleEndianUInt16(at: offset + 30))
      let commentLength = Int(try archive.littleEndianUInt16(at: offset + 32))
      let localOffset = Int(try archive.littleEndianUInt32(at: offset + 42))
      let nameStart = offset + 46
      let nameEnd = nameStart + nameLength
      guard nameEnd <= archive.count else { throw MCBEEditorError.invalidArchive("文件名越界") }
      let nameData = archive.subdata(in: nameStart..<nameEnd)
      let path: String
      if flags & 0x0800 != 0 {
        guard let decoded = String(data: nameData, encoding: .utf8) else {
          throw MCBEEditorError.invalidArchive("UTF-8 文件名损坏")
        }
        path = decoded
      } else {
        path =
          String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .isoLatin1)
          ?? ""
      }
      entries.append(
        Entry(
          path: path, method: method, crc32: crc, compressedSize: compressedSize,
          uncompressedSize: uncompressedSize, localHeaderOffset: localOffset))
      offset = nameEnd + extraLength + commentLength
    }
    return entries
  }

  private static func validateForExtraction(
    _ entries: [Entry]
  ) throws -> [(entry: Entry, safeRelativePath: String)] {
    var totalSize: Int64 = 0
    var normalizedPaths = Set<String>()
    var result = [(entry: Entry, safeRelativePath: String)]()
    result.reserveCapacity(entries.count)

    for entry in entries {
      guard let safeRelative = sanitizedRelativePath(entry.path) else {
        throw MCBEEditorError.invalidArchive("包含不安全路径：\(entry.path)")
      }
      let uncompressed = Int64(entry.uncompressedSize)
      let compressed = Int64(entry.compressedSize)
      guard uncompressed <= maximumSingleEntrySize else {
        throw MCBEEditorError.invalidArchive("单个文件解压后过大：\(entry.path)")
      }
      let (updatedTotal, overflow) = totalSize.addingReportingOverflow(uncompressed)
      guard !overflow, updatedTotal <= maximumTotalExtractedSize else {
        throw MCBEEditorError.invalidArchive("解压后的文件总量超过安全上限")
      }
      totalSize = updatedTotal

      if uncompressed > 64 * 1_024 * 1_024 {
        guard compressed > 0,
          uncompressed / max(1, compressed) <= maximumSuspiciousExpansionRatio
        else {
          throw MCBEEditorError.invalidArchive("压缩比异常：\(entry.path)")
        }
      }

      // iOS application storage is normally case-insensitive. Rejecting
      // case-only and duplicate paths avoids order-dependent overwrites.
      let collisionKey =
        safeRelative
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        .precomposedStringWithCanonicalMapping
        .lowercased()
      guard normalizedPaths.insert(collisionKey).inserted else {
        throw MCBEEditorError.invalidArchive("ZIP 包含重复路径：\(entry.path)")
      }
      result.append((entry, safeRelative))
    }
    return result
  }

  private static func sanitizedRelativePath(_ path: String) -> String? {
    let normalized = path.replacingOccurrences(of: "\\", with: "/")
    guard !normalized.hasPrefix("/"), !normalized.contains(":") else { return nil }
    let components = normalized.split(separator: "/", omittingEmptySubsequences: true)
    guard !components.contains(where: { $0 == ".." || $0 == "." }) else { return nil }
    return components.joined(separator: "/") + (normalized.hasSuffix("/") ? "/" : "")
  }
}
