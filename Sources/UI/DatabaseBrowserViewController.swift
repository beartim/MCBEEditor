import UIKit

final class DatabaseBrowserViewController: UITableViewController, UISearchResultsUpdating {
    private let session: WorldSession
    private var database: MojangLevelDB?
    private var allEntries: [(key: Data, value: Data?)] = []
    private var filteredEntries: [(key: Data, value: Data?)] = []
    private let search = UISearchController(searchResultsController: nil)

    init(session: WorldSession) {
        self.session = session
        super.init(style: .plain)
        title = "数据库"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "搜索 UTF-8、十六进制或已解析区块键"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(loadEntries))
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(worldDidChange),
            name: WorldSession.worldDidChangeNotification,
            object: session
        )
        loadEntries()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func worldDidChange() {
        database = nil
        allEntries.removeAll()
        filteredEntries.removeAll()
        tableView.reloadData()
        loadEntries()
    }

    @objc private func loadEntries() {
        let overlay = showBusy("读取 LevelDB…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let db = try self.session.database()
                let entries = try db.entries(includeValues: false, limit: 50_000)
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.database = db
                    self.allEntries = entries
                    self.applyFilter()
                    self.navigationItem.prompt = entries.count == 50_000 ? "显示前 50,000 个键" : "\(entries.count) 个键"
                }
            } catch {
                DispatchQueue.main.async { overlay.removeFromSuperview(); self.showError(error, title: "数据库读取失败") }
            }
        }
    }

    func updateSearchResults(for searchController: UISearchController) { applyFilter() }

    private func applyFilter() {
        let query = search.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if query.isEmpty {
            filteredEntries = allEntries
        } else {
            filteredEntries = allEntries.filter { entry in
                entry.key.hexString.lowercased().contains(query) ||
                (String(data: entry.key, encoding: .utf8)?.lowercased().contains(query) == true) ||
                (BedrockDBKey.parse(entry.key)?.description.lowercased().contains(query) == true)
            }
        }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { filteredEntries.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let key = filteredEntries[indexPath.row].key
        let cell = tableView.dequeueReusableCell(withIdentifier: "DBCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "DBCell")
        cell.textLabel?.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        cell.detailTextLabel?.font = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.textLabel?.numberOfLines = 1
        cell.detailTextLabel?.numberOfLines = 2
        let parsed = BedrockDBKey.parse(key)
        let utf8 = String(data: key, encoding: .utf8)?.replacingOccurrences(of: "\0", with: "\\0")
        cell.textLabel?.text = parsed?.description ?? "Raw key (\(key.count) bytes)"
        cell.detailTextLabel?.text = utf8?.isEmpty == false ? utf8! : key.hexString
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let database = database else { return }
        let key = filteredEntries[indexPath.row].key
        do {
            let value = try database.get(key) ?? Data()
            let detail = DatabaseValueViewController(title: BedrockDBKey.parse(key)?.description ?? "Raw key", data: value, editable: false)
            navigationController?.pushViewController(detail, animated: true)
        } catch { showError(error, title: "读取键值失败") }
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let key = filteredEntries[indexPath.row].key
        let copy = UIContextualAction(style: .normal, title: "复制键") { [weak self] _, _, completion in
            let utf8 = String(data: key, encoding: .utf8)
            UIPasteboard.general.string = utf8?.isEmpty == false ? utf8 : key.hexString
            self?.navigationItem.prompt = "键已复制"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.navigationItem.prompt = nil }
            completion(true)
        }
        copy.backgroundColor = .systemBlue

        let export = UIContextualAction(style: .normal, title: "导出值") { [weak self] _, sourceView, completion in
            self?.exportValue(for: key, sourceView: sourceView)
            completion(true)
        }
        export.backgroundColor = .systemGreen
        return UISwipeActionsConfiguration(actions: [export, copy])
    }

    private func exportValue(for key: Data, sourceView: UIView) {
        guard let database = database else { return }
        do {
            let value = try database.get(key) ?? Data()
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("leveldb-value-\(UUID().uuidString.prefix(8)).bin")
            try value.write(to: output, options: .atomic)
            let activity = UIActivityViewController(activityItems: [output], applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = sourceView
            activity.popoverPresentationController?.sourceRect = sourceView.bounds
            present(activity, animated: true)
        } catch {
            showError(error, title: "导出键值失败")
        }
    }
}
