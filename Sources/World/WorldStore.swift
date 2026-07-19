import Foundation

struct ImportedWorld: Codable, Hashable {
  enum SourceKind: String, Codable {
    case mcworld
    case folder
  }

  let id: UUID
  var name: String
  let relativePath: String
  let importedAt: Date
  let sourceKind: SourceKind
}

final class WorldStore {
  static let shared = WorldStore()

  private let manager: FileManager
  private let lock = NSLock()
  let rootURL: URL
  let worldsURL: URL
  let metadataRootURL: URL
  private let indexURL: URL
  private let deletionStagingURL: URL
  private var storedWorlds: [ImportedWorld] = []

  var worlds: [ImportedWorld] {
    lock.lock()
    defer { lock.unlock() }
    return storedWorlds
  }

  private convenience init() {
    let manager = FileManager.default
    let applicationSupport =
      manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? manager.urls(for: .documentDirectory, in: .userDomainMask).first
      ?? manager.temporaryDirectory
    self.init(
      rootURL: applicationSupport.appendingPathComponent("MCBEEditor", isDirectory: true),
      manager: manager
    )
  }

  /// Internal root injection keeps file-transaction recovery testable without
  /// changing the production singleton API.
  init(rootURL: URL, manager: FileManager = .default) {
    self.manager = manager
    self.rootURL = rootURL
    worldsURL = rootURL.appendingPathComponent("Worlds", isDirectory: true)
    metadataRootURL = rootURL.appendingPathComponent("Metadata", isDirectory: true)
    indexURL = rootURL.appendingPathComponent("worlds.json")
    deletionStagingURL = rootURL.appendingPathComponent(".DeletionStaging", isDirectory: true)
    try? manager.createDirectory(at: worldsURL, withIntermediateDirectories: true)
    try? manager.createDirectory(at: metadataRootURL, withIntermediateDirectories: true)
    try? manager.createDirectory(at: deletionStagingURL, withIntermediateDirectories: true)
    load()
  }

  func worldURL(for world: ImportedWorld) -> URL {
    rootURL.appendingPathComponent(world.relativePath, isDirectory: true)
  }

  func metadataURL(for world: ImportedWorld) -> URL {
    metadataRootURL.appendingPathComponent(world.id.uuidString, isDirectory: true)
  }

  func add(_ world: ImportedWorld) throws {
    lock.lock()
    defer { lock.unlock() }
    storedWorlds.append(world)
    storedWorlds.sort { $0.importedAt > $1.importedAt }
    do {
      try saveLocked()
    } catch {
      storedWorlds.removeAll { $0.id == world.id }
      throw error
    }
  }

  func remove(_ world: ImportedWorld) throws {
    lock.lock()
    defer { lock.unlock() }
    guard storedWorlds.contains(where: { $0.id == world.id }) else { return }

    let sourceWorld = worldURL(for: world)
    let sourceMetadata = metadataURL(for: world)
    let stagingRoot = deletionStagingURL.appendingPathComponent(
      world.id.uuidString, isDirectory: true)
    let stagedWorld = stagingRoot.appendingPathComponent("World", isDirectory: true)
    let stagedMetadata = stagingRoot.appendingPathComponent("Metadata", isDirectory: true)
    if manager.fileExists(atPath: stagingRoot.path) {
      throw MCBEEditorError.io("该世界存在尚未恢复的删除事务，请重新启动应用后再试")
    }
    try manager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)

    var movedWorld = false
    var movedMetadata = false
    do {
      if manager.fileExists(atPath: sourceWorld.path) {
        try manager.moveItem(at: sourceWorld, to: stagedWorld)
        movedWorld = true
      }
      if manager.fileExists(atPath: sourceMetadata.path) {
        try manager.moveItem(at: sourceMetadata, to: stagedMetadata)
        movedMetadata = true
      }

      let previous = storedWorlds
      storedWorlds.removeAll { $0.id == world.id }
      do {
        try saveLocked()
      } catch {
        storedWorlds = previous
        throw error
      }
      try? removeItemRecursively(at: stagingRoot)
    } catch {
      var rollbackError: Error?
      do {
        if movedWorld, manager.fileExists(atPath: stagedWorld.path) {
          try manager.moveItem(at: stagedWorld, to: sourceWorld)
        }
        if movedMetadata, manager.fileExists(atPath: stagedMetadata.path) {
          try manager.moveItem(at: stagedMetadata, to: sourceMetadata)
        }
        try? removeItemRecursively(at: stagingRoot)
      } catch {
        rollbackError = error
      }
      if let rollbackError = rollbackError {
        throw MCBEEditorError.io(
          "删除世界失败，且回滚文件时失败：\(error.localizedDescription)；回滚：\(rollbackError.localizedDescription)")
      }
      throw error
    }
  }

  func rename(_ world: ImportedWorld, to requestedName: String) throws {
    let name = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { throw MCBEEditorError.io("世界名称不能为空") }

    lock.lock()
    defer { lock.unlock() }
    guard let index = storedWorlds.firstIndex(where: { $0.id == world.id }) else {
      throw MCBEEditorError.io("世界索引中不存在该存档")
    }
    let previousName = storedWorlds[index].name
    let root = worldURL(for: world)
    let snapshot = try captureWorldNameFiles(at: root)
    do {
      try writeWorldName(name, at: root)
      storedWorlds[index].name = name
      try saveLocked()
    } catch {
      storedWorlds[index].name = previousName
      do {
        try restoreWorldNameFiles(snapshot, at: root)
      } catch let rollbackError {
        throw MCBEEditorError.io(
          "重命名世界失败，且回滚名称文件时失败：\(error.localizedDescription)；回滚：\(rollbackError.localizedDescription)"
        )
      }
      throw error
    }
  }

  func duplicate(_ world: ImportedWorld) throws -> ImportedWorld {
    let source = worldURL(for: world)
    guard manager.fileExists(atPath: source.path) else {
      throw MCBEEditorError.io("原世界目录不存在")
    }

    let id = UUID()
    let destination = worldsURL.appendingPathComponent(id.uuidString, isDirectory: true)
    let name = uniqueCopyName(for: world.name)
    try? manager.removeItem(at: destination)

    do {
      try manager.copyItem(at: source, to: destination)
      try writeWorldName(name, at: destination)
      let copy = ImportedWorld(
        id: id,
        name: name,
        relativePath: "Worlds/\(id.uuidString)",
        importedAt: Date(),
        sourceKind: world.sourceKind
      )
      let sourceMetadata = metadataURL(for: world)
      let destinationMetadata = metadataURL(for: copy)
      if manager.fileExists(atPath: sourceMetadata.path) {
        try? manager.removeItem(at: destinationMetadata)
        try manager.copyItem(at: sourceMetadata, to: destinationMetadata)
      }
      try add(copy)
      return copy
    } catch {
      try? manager.removeItem(at: destination)
      try? manager.removeItem(
        at: metadataRootURL.appendingPathComponent(id.uuidString, isDirectory: true))
      throw error
    }
  }

  private func uniqueCopyName(for sourceName: String) -> String {
    lock.lock()
    defer { lock.unlock() }
    let names = Set(storedWorlds.map { $0.name })
    let base = "\(sourceName) 副本"
    if !names.contains(base) { return base }
    var index = 2
    while names.contains("\(base) \(index)") { index += 1 }
    return "\(base) \(index)"
  }

  private func removeItemRecursively(at url: URL) throws {
    var isDirectory: ObjCBool = false
    guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
    if isDirectory.boolValue {
      let children = try manager.contentsOfDirectory(
        at: url, includingPropertiesForKeys: nil, options: [])
      for child in children { try removeItemRecursively(at: child) }
    }
    try manager.removeItem(atPath: url.path)
  }

  private struct WorldNameFilesSnapshot {
    let levelDat: Data?
    let levelName: Data?
  }

  private func captureWorldNameFiles(at rootURL: URL) throws -> WorldNameFilesSnapshot {
    let levelDatURL = rootURL.appendingPathComponent("level.dat")
    let levelNameURL = rootURL.appendingPathComponent("levelname.txt")
    return try WorldNameFilesSnapshot(
      levelDat: manager.fileExists(atPath: levelDatURL.path) ? Data(contentsOf: levelDatURL) : nil,
      levelName: manager.fileExists(atPath: levelNameURL.path)
        ? Data(contentsOf: levelNameURL) : nil
    )
  }

  private func restoreWorldNameFiles(
    _ snapshot: WorldNameFilesSnapshot,
    at rootURL: URL
  ) throws {
    try restoreFile(snapshot.levelDat, at: rootURL.appendingPathComponent("level.dat"))
    try restoreFile(snapshot.levelName, at: rootURL.appendingPathComponent("levelname.txt"))
  }

  private func restoreFile(_ data: Data?, at url: URL) throws {
    if let data {
      try AtomicFile.write(data, to: url)
    } else if manager.fileExists(atPath: url.path) {
      try removeItemRecursively(at: url)
    }
  }

  private func writeWorldName(_ name: String, at rootURL: URL) throws {
    let document = WorldDocument(rootURL: rootURL)
    var levelDat = try document.readLevelDat()
    guard case .compound(var tags) = levelDat.document.root else {
      throw MCBEEditorError.malformedData("level.dat 根节点不是 Compound")
    }
    if let index = tags.firstIndex(where: { $0.name == "LevelName" }) {
      tags[index].value = .string(name)
    } else {
      tags.append(NBTNamedTag(name: "LevelName", value: .string(name)))
    }
    levelDat.document.root = .compound(tags)
    try document.writeLevelDat(levelDat)
    try AtomicFile.write(Data(name.utf8), to: rootURL.appendingPathComponent("levelname.txt"))
  }

  private func load() {
    do {
      let data = try Data(contentsOf: indexURL)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      storedWorlds = try decoder.decode([ImportedWorld].self, from: data)
    } catch {
      storedWorlds = []
    }

    recoverInterruptedDeletions()
    let previousCount = storedWorlds.count
    storedWorlds = storedWorlds.filter { manager.fileExists(atPath: worldURL(for: $0).path) }
    if storedWorlds.count != previousCount { try? saveLocked() }
  }

  /// A deletion is committed by removing the world from `worlds.json`. If
  /// the process stops before that commit, the index still contains the
  /// world and the staged files are restored on the next launch. If the
  /// commit already happened, the staging directory is safe to discard.
  private func recoverInterruptedDeletions() {
    guard
      let stagedTransactions = try? manager.contentsOfDirectory(
        at: deletionStagingURL,
        includingPropertiesForKeys: nil,
        options: []
      )
    else { return }

    for stagingRoot in stagedTransactions {
      guard let worldID = UUID(uuidString: stagingRoot.lastPathComponent) else { continue }
      guard let indexedWorld = storedWorlds.first(where: { $0.id == worldID }) else {
        try? removeItemRecursively(at: stagingRoot)
        continue
      }

      let stagedWorld = stagingRoot.appendingPathComponent("World", isDirectory: true)
      let stagedMetadata = stagingRoot.appendingPathComponent("Metadata", isDirectory: true)
      let destinationWorld = worldURL(for: indexedWorld)
      let destinationMetadata = metadataURL(for: indexedWorld)
      do {
        if manager.fileExists(atPath: stagedWorld.path),
          !manager.fileExists(atPath: destinationWorld.path)
        {
          try manager.createDirectory(
            at: destinationWorld.deletingLastPathComponent(),
            withIntermediateDirectories: true)
          try manager.moveItem(at: stagedWorld, to: destinationWorld)
        }
        if manager.fileExists(atPath: stagedMetadata.path),
          !manager.fileExists(atPath: destinationMetadata.path)
        {
          try manager.createDirectory(
            at: destinationMetadata.deletingLastPathComponent(),
            withIntermediateDirectories: true)
          try manager.moveItem(at: stagedMetadata, to: destinationMetadata)
        }
        try? removeItemRecursively(at: stagingRoot)
      } catch {
        // Leave the transaction in place for a later recovery attempt.
      }
    }
  }

  private func saveLocked() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(storedWorlds)
    try AtomicFile.write(data, to: indexURL)
  }
}
