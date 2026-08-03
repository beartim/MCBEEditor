import Foundation

enum ChunkCoordinateSearch {
  /// Parses an exact chunk coordinate written as `(x,z)`. Whitespace around
  /// either signed Int32 coordinate is accepted; every other shape returns nil.
  static func parse(_ value: String) -> (x: Int32, z: Int32)? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.first == "(", trimmed.last == ")" else { return nil }
    let parts = trimmed.dropFirst().dropLast().split(
      separator: ",", omittingEmptySubsequences: false)
    guard parts.count == 2,
      let x = Int64(String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)),
      let z = Int64(String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)),
      x >= Int64(Int32.min), x <= Int64(Int32.max),
      z >= Int64(Int32.min), z <= Int64(Int32.max)
    else { return nil }
    return (Int32(x), Int32(z))
  }
}
