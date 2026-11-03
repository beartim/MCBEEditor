import Foundation

/// Identity for one row in a list snapshot. Storage record indexes can change
/// after saves/deletions, so they cannot identify rows or their viewed badges.
struct WorldObjectListItem {
    let id = UUID().uuidString
    var object: BedrockWorldObject
}
