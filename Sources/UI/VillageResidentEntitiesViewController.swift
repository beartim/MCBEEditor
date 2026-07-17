import UIKit

final class VillageResidentEntitiesViewController: UITableViewController, UISearchResultsUpdating {
    private let session: WorldSession
    private let allObjects: [BedrockWorldObject]
    private let residentKind: VillageResidentEntityKind
    private let searchController = UISearchController(searchResultsController: nil)
    private var shownObjects = [BedrockWorldObject]()

    init(session: WorldSession, objects: [BedrockWorldObject], residentKind: VillageResidentEntityKind) {
        self.session = session
        self.allObjects = objects.sorted { lhs, rhs in
            let left = lhs.uniqueID ?? Int64.min
            let right = rhs.uniqueID ?? Int64.min
            if left != right { return left < right }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        self.residentKind = residentKind
        super.init(style: .insetGrouped)
        title = residentKind.displayName
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜索名称、ID、坐标或来源"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        navigationItem.prompt = "Dwellers ID（实体 UniqueID）匹配到 \(allObjects.count) 个\(residentKind.displayName)"
        applyFilter()
    }

    func updateSearchResults(for searchController: UISearchController) { applyFilter() }

    private func applyFilter() {
        let query = searchController.searchBar.text?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        shownObjects = allObjects.filter { object in
            query.isEmpty ||
            object.displayName.lowercased().contains(query) ||
            object.identifier.lowercased().contains(query) ||
            object.coordinateText.lowercased().contains(query) ||
            object.source.rawValue.lowercased().contains(query) ||
            object.uniqueID.map { String($0).contains(query) } == true
        }
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { shownObjects.count }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        shownObjects.isEmpty
            ? "Dwellers 中没有匹配到此类型的世界实体。"
            : "点按实体可查看 UniqueID、坐标并进入 NBT 编辑页面。"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let object = shownObjects[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "VillageResidentEntityCell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "VillageResidentEntityCell")
        cell.textLabel?.text = object.displayName
        var details = object.coordinateText
        if let uniqueID = object.uniqueID { details += "；UniqueID=\(uniqueID)" }
        cell.detailTextLabel?.text = details
        cell.detailTextLabel?.numberOfLines = 2
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.imageView?.image = UIImage(systemName: residentKind.iconName) ?? UIImage(systemName: "person.fill")
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        showDetails(shownObjects[indexPath.row], sourceRect: tableView.rectForRow(at: indexPath))
    }

    private func showDetails(_ object: BedrockWorldObject, sourceRect: CGRect) {
        let dimension = BedrockDimension(rawValue: object.dimension)?.displayName ?? "维度 \(object.dimension)"
        var message = "\(object.identifier)\n\(dimension)；\(object.coordinateText)\n来源：\(object.source.rawValue)"
        if let uniqueID = object.uniqueID { message += "\nUniqueID：\(uniqueID)" }
        let alert = UIAlertController(title: object.displayName, message: message, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "编辑 NBT", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let controller = WorldObjectNBTEditorViewController(
                object: object,
                session: self.session,
                onSave: { [weak self] in self?.session.invalidateAfterExternalChange() }
            )
            self.navigationController?.pushViewController(controller, animated: true)
        })
        alert.addAction(UIAlertAction(title: "复制坐标", style: .default) { _ in
            UIPasteboard.general.string = object.coordinateText
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = tableView
            popover.sourceRect = sourceRect
        }
        present(alert, animated: true)
    }
}
