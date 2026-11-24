import Foundation

@main
struct NBTSearchLocationTests {
  static func main() throws {
    func tag(_ name: String, _ value: NBTValue) -> NBTNamedTag {
      NBTNamedTag(name: name, value: value)
    }
    let root = NBTValue.compound([
      tag("Bag", .list(.compound, [
        .compound([tag("Name", .string("first"))]),
        .compound([tag("Name", .string("second")), tag("Name", .string("third"))])
      ])),
      tag("Bag[1]/Name", .string("literal")),
      tag("", .int(1)),
      tag("line\nbreak", .int(2)),
      tag("Name#2", .string("suffix"))
    ])
    let matches = NBTTreeRows.search(in: root, query: "Name")
    let paths = matches.map(\.pathDescription)
    precondition(paths == ["/Bag[0]/Name", "/Bag[1]/Name", "/Bag[1]/Name#2",
                           #"/Bag\[1\]\/Name"#, ##"/Name\#2"##], "Ambiguous search paths: \(paths)")
    let rootRows = NBTTreeRows.visibleChildren(of: root, expanded: [[]])
    precondition(rootRows[2].pathDescription == #"/\e"#)
    precondition(rootRows[3].pathDescription == #"/line\nbreak"#)
    let target = matches[2]
    let open = Set(target.path.indices.map { Array(target.path.prefix($0)) })
    let visible = NBTTreeRows.visibleChildren(of: root, expanded: open)
    precondition(visible.filter { $0.path == target.path }.map(\.value.summary) == ["third"])
    precondition(NBTTreeMutation.value(at: target.path, in: root)?.summary == "third")
    let edited = try NBTTreeMutation.replacingValue(at: target.path, in: root, with: .string("edited"))
    precondition(NBTTreeMutation.value(at: matches[1].path, in: edited)?.summary == "second")
    precondition(NBTTreeMutation.value(at: target.path, in: edited)?.summary == "edited")
    let renamed = try NBTTreeMutation.renaming(at: target.path, to: "Alias", in: root)
    precondition(NBTTreeRows.search(in: renamed, query: "Alias").first?.value.summary == "third")
    let removed = try NBTTreeMutation.deleting(at: [matches[1].path, matches[2].path], in: root)
    precondition(NBTTreeRows.search(in: removed, query: "Name").count == 3)
    let rootList = NBTTreeRows.search(in: .list(.int, [.int(100)]), query: "100")
    precondition(rootList.first?.pathDescription == "/[0]")
    precondition(NBTTreeRows.search(in: root, query: "/Bag[0]/Name").isEmpty)
    let scalar = NBTDocument(rootName: "Health", root: .int(17))
    for term in ["", "Health", "17", "Int"] {
      let result = NBTTreeRows.rows(in: scalar, expanded: [], query: term)
      precondition(result.count == 1 && result[0].path == [] && result[0].pathDescription == "/")
    }
    precondition(NBTTreeRows.rows(in: scalar, expanded: [], query: "missing").isEmpty)
    print("PASS NBT search paths, exact nested/duplicate targets and mutations")
  }
}
