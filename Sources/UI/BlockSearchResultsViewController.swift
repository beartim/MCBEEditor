import UIKit

final class BlockSearchResultsViewController: UITableViewController, UISearchResultsUpdating {
    private let session: WorldSession
    private let result: BedrockBlockSearchScanResult
    private let searchController = UISearchController(searchResultsController: nil)
    private var shownHits: [BedrockBlockSearchHit]

    init(session: WorldSession, result: BedrockBlockSearchScanResult) {
        self.session = session
        self.result = result
        self.shownHits = result.hits
        super.init(style: .insetGrouped)
        title = "方块搜索结果"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "筛选方块名称、维度或坐标"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        updatePrompt()
    }

    func updateSearchResults(for searchController: UISearchController) {
        let query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        shownHits = result.hits.filter {
            query.isEmpty || $0.coordinateText.lowercased().contains(query) || $0.dimensionName.lowercased().contains(query) || $0.blockDescription.lowercased().contains(query)
        }
        tableView.reloadData()
        updatePrompt()
    }

    private func updatePrompt() {
        var text = "显示 \(shownHits.count) / \(result.hits.count) 个方块"
        if result.truncated { text += " · 已达到结果上限" }
        if result.skippedSubChunkCount > 0 { text += " · 跳过 \(result.skippedSubChunkCount) 个旧版 SubChunk" }
        navigationItem.prompt = text
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { shownHits.count }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { "点按结果会切换到地图栏目、定位并选中对应方块。" }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let hit = shownHits[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "BlockSearchHitCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "BlockSearchHitCell")
        cell.textLabel?.text = hit.blockDescription
        cell.detailTextLabel?.text = "\(hit.dimensionName) · \(hit.coordinateText)"
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.imageView?.image = UIImage(systemName: "cube.fill")
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let hit = shownHits[indexPath.row]
        if let workspace = tabBarController as? WorldDetailTabBarController {
            workspace.showMapBlockSearchHit(hit, result: result)
        } else {
            session.rememberBlockSearchResult(result)
            tabBarController?.selectedIndex = 0
            session.requestMapBlockSelection(x: hit.x, y: hit.y, z: hit.z, dimension: hit.dimension)
        }
    }
}
