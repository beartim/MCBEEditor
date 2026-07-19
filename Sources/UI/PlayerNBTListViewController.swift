import UIKit

final class PlayerNBTListViewController: UITableViewController, UISearchResultsUpdating {
    private let session: WorldSession
    private let store: PlayerNBTStore
    private let queue = DispatchQueue(label: "com.wzn.mcbeeditor.player-nbt", qos: .userInitiated)
    private let searchController = UISearchController(searchResultsController: nil)
    private var allRecords = [PlayerNBTRecord]()
    private var shownRecords = [PlayerNBTRecord]()
    private var loadGeneration = 0

    init(session: WorldSession) {
        self.session = session
        self.store = PlayerNBTStore(session: session)
        super.init(style: .insetGrouped)
        title = "玩家 NBT"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜索玩家名称、键或 ID"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(loadRecords))
        loadRecords()
    }

    @objc private func loadRecords() {
        loadGeneration += 1
        let generation = loadGeneration
        navigationItem.rightBarButtonItem?.isEnabled = false
        navigationItem.prompt = "正在读取玩家 NBT…"
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let records = try self.store.records()
                DispatchQueue.main.async {
                    guard generation == self.loadGeneration else { return }
                    self.navigationItem.rightBarButtonItem?.isEnabled = true
                    self.allRecords = records
                    self.applyFilter()
                    self.navigationItem.prompt = records.isEmpty ? "未找到玩家数据键" : "共 \(records.count) 个玩家记录"
                }
            } catch {
                DispatchQueue.main.async {
                    guard generation == self.loadGeneration else { return }
                    self.navigationItem.rightBarButtonItem?.isEnabled = true
                    self.navigationItem.prompt = nil
                    self.showError(error, title: "读取玩家 NBT 失败")
                }
            }
        }
    }

    func updateSearchResults(for searchController: UISearchController) { applyFilter() }

    private func applyFilter() {
        let query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        shownRecords = allRecords.filter { record in
            query.isEmpty || record.displayName.lowercased().contains(query) || record.keyText.lowercased().contains(query)
        }
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { shownRecords.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let record = shownRecords[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "PlayerNBTCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "PlayerNBTCell")
        cell.textLabel?.text = record.displayName
        cell.detailTextLabel?.text = record.keyText
        cell.detailTextLabel?.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.imageView?.image = UIImage(systemName: record.keyText == "~local_player" || record.keyText == "LocalPlayer" ? "person.crop.circle.fill" : "person.2.fill")
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let record = shownRecords[indexPath.row]
        let controller = PlayerNBTEditorViewController(record: record, store: store) { [weak self] in
            self?.loadRecords()
        }
        navigationController?.pushViewController(controller, animated: true)
    }
}
