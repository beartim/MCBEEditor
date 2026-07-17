import UIKit

final class MapSelectionResultsViewController: UITableViewController, UISearchResultsUpdating {
    private let session: WorldSession
    private let boundsText: String
    private let objects: [BedrockWorldObject]
    private let onSelect: (BedrockWorldObject) -> Void
    private let onLocate: (BedrockWorldObject) -> Void
    private let searchController = UISearchController(searchResultsController: nil)
    private var shown = [BedrockWorldObject]()

    init(
        session: WorldSession,
        objects: [BedrockWorldObject],
        boundsText: String,
        onSelect: @escaping (BedrockWorldObject) -> Void,
        onLocate: @escaping (BedrockWorldObject) -> Void
    ) {
        self.session = session
        self.objects = objects
        self.boundsText = boundsText
        self.onSelect = onSelect
        self.onLocate = onLocate
        super.init(style: .insetGrouped)
        title = "框选结果"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜索实体、方块实体、ID 或坐标"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        navigationItem.prompt = summaryText
        applyFilter()
    }

    private var summaryText: String {
        let entities = objects.filter { $0.kind == .entity }.count
        let blockEntities = objects.count - entities
        return "\(boundsText)；实体 \(entities)，方块实体 \(blockEntities)"
    }

    func updateSearchResults(for searchController: UISearchController) { applyFilter() }

    private func applyFilter() {
        let query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        shown = objects.filter { object in
            query.isEmpty || object.displayName.lowercased().contains(query) ||
                object.identifier.lowercased().contains(query) ||
                object.coordinateText.lowercased().contains(query) ||
                object.source.rawValue.lowercased().contains(query)
        }
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "实体" : "方块实体"
    }

    private func objects(in section: Int) -> [BedrockWorldObject] {
        shown.filter { $0.kind == (section == 0 ? .entity : .blockEntity) }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        objects(in: section).count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let object = objects(in: indexPath.section)[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "SelectionObjectCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "SelectionObjectCell")
        cell.textLabel?.text = object.displayName
        cell.detailTextLabel?.text = object.subtitle
        cell.detailTextLabel?.numberOfLines = 2
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.imageView?.image = UIImage(systemName: object.kind == .entity ? "person.fill" : "shippingbox.fill")
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        showDetails(objects(in: indexPath.section)[indexPath.row], sourceRect: tableView.rectForRow(at: indexPath))
    }

    private func showDetails(_ object: BedrockWorldObject, sourceRect: CGRect) {
        let dimension = BedrockDimension(rawValue: object.dimension)?.displayName ?? "维度 \(object.dimension)"
        var message = "\(object.identifier)\n\(dimension)；\(object.coordinateText)\n来源：\(object.source.rawValue)"
        if let uniqueID = object.uniqueID { message += "\nUniqueID：\(uniqueID)" }
        if object.itemCount > 0 { message += "\n物品槽：\(object.itemCount)" }
        let alert = UIAlertController(title: object.displayName, message: message, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "在地图中选中并闪烁", style: .default) { [weak self] _ in
            self?.onSelect(object)
        })
        alert.addAction(UIAlertAction(title: "定位到地图中心", style: .default) { [weak self] _ in
            self?.onLocate(object)
        })
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
