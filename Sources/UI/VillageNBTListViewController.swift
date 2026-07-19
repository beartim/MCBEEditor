import UIKit

final class VillageNBTListViewController: UITableViewController, UISearchResultsUpdating {
    private struct VillageSection {
        let identifier: String
        let title: String
        let records: [VillageNBTRecord]
    }

    private let store: VillageNBTStore
    private let villageIdentifierFilter: String?
    private let villageDisplayName: String?
    private let onSave: () -> Void
    private let queue = DispatchQueue(label: "com.wzn.mcbeeditor.village-nbt", qos: .userInitiated)
    private let searchController = UISearchController(searchResultsController: nil)
    private var allRecords = [VillageNBTRecord]()
    private var shownSections = [VillageSection]()
    private var diagnostics = [String]()
    private var loadGeneration = 0

    init(
        session: WorldSession,
        villageIdentifier: String? = nil,
        villageDisplayName: String? = nil,
        onSave: @escaping () -> Void = {}
    ) {
        self.store = VillageNBTStore(session: session)
        self.villageIdentifierFilter = villageIdentifier
        self.villageDisplayName = villageDisplayName
        self.onSave = onSave
        super.init(style: .insetGrouped)
        title = villageDisplayName ?? "村庄 NBT"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜索村庄、UUID、记录类型、键或 NBT"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(loadRecords)
        )
        loadRecords()
    }

    @objc private func loadRecords() {
        loadGeneration += 1
        let generation = loadGeneration
        navigationItem.rightBarButtonItem?.isEnabled = false
        navigationItem.prompt = "正在扫描并分组村庄 NBT…"
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let scan = try self.store.scanRecords()
                DispatchQueue.main.async {
                    guard generation == self.loadGeneration else { return }
                    self.navigationItem.rightBarButtonItem?.isEnabled = true
                    let records = self.villageIdentifierFilter.map { identifier in
                        scan.records.filter { $0.villageIdentifier == identifier }
                    } ?? scan.records
                    self.allRecords = records
                    self.diagnostics = scan.diagnostics
                    self.applyFilter()
                    let villageCount = Set(records.map(\.villageIdentifier)).count
                    if records.isEmpty {
                        self.navigationItem.prompt = self.villageIdentifierFilter == nil
                            ? "未找到 mVillages 或 VILLAGE_* 记录"
                            : "未找到该村庄的 NBT 记录"
                    } else {
                        let warning = scan.diagnostics.isEmpty ? "" : "；跳过 \(scan.diagnostics.count) 条异常记录"
                        if self.villageIdentifierFilter != nil {
                            self.navigationItem.prompt = "信息、兴趣点、居民、声望；共 \(records.count) 个可修改文档\(warning)"
                        } else {
                            self.navigationItem.prompt = "\(villageCount) 个村庄，\(records.count) 个可修改文档\(warning)"
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard generation == self.loadGeneration else { return }
                    self.navigationItem.rightBarButtonItem?.isEnabled = true
                    self.navigationItem.prompt = nil
                    self.showError(error, title: "读取村庄 NBT 失败")
                }
            }
        }
    }

    func updateSearchResults(for searchController: UISearchController) { applyFilter() }

    private func applyFilter() {
        let query = searchController.searchBar.text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let grouped = Dictionary(grouping: allRecords, by: \.villageIdentifier)
        shownSections = grouped.compactMap { identifier, records -> VillageSection? in
            guard let first = records.first else { return nil }
            let sorted = records.sorted {
                if $0.kind.sortOrder != $1.kind.sortOrder { return $0.kind.sortOrder < $1.kind.sortOrder }
                return $0.stableID < $1.stableID
            }
            if query.isEmpty {
                return VillageSection(identifier: identifier, title: first.villageDisplayName, records: sorted)
            }
            let villageMatches = first.villageDisplayName.lowercased().contains(query) || identifier.lowercased().contains(query)
            let matches = villageMatches ? sorted : sorted.filter { record in
                record.displayName.lowercased().contains(query) ||
                record.kind.rawValue.lowercased().contains(query) ||
                record.kind.displayName.lowercased().contains(query) ||
                record.keyText.lowercased().contains(query) ||
                record.document.rootName.lowercased().contains(query) ||
                record.detailDescription.lowercased().contains(query)
            }
            guard !matches.isEmpty else { return nil }
            return VillageSection(identifier: identifier, title: first.villageDisplayName, records: matches)
        }.sorted { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        tableView.reloadData()
    }

    private func record(at indexPath: IndexPath) -> VillageNBTRecord {
        shownSections[indexPath.section].records[indexPath.row]
    }

    override func numberOfSections(in tableView: UITableView) -> Int { shownSections.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        shownSections[section].records.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        shownSections[section].title
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == shownSections.count - 1 else { return nil }
        let warning = diagnostics.isEmpty ? "" : " 有 \(diagnostics.count) 条无法解析的村庄记录已跳过。"
        if villageIdentifierFilter != nil {
            return "此处列出该村庄的信息、兴趣点、居民和声望记录；点按任一项可修改全部 NBT 节点。\(warning)"
        }
        return "不同村庄已分开显示。兼容旧版 mVillages 与新版 VILLAGE_*_INFO、POI、DWELLERS、PLAYERS；点按任一记录即可修改全部 NBT 节点。\(warning)"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let record = record(at: indexPath)
        let cell = tableView.dequeueReusableCell(withIdentifier: "VillageNBTCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "VillageNBTCell")
        cell.textLabel?.text = record.displayName
        cell.textLabel?.font = .preferredFont(forTextStyle: .headline)
        cell.detailTextLabel?.text = record.detailDescription
        cell.detailTextLabel?.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 2
        cell.imageView?.image = UIImage(systemName: record.kind.iconName) ?? UIImage(systemName: "doc.text")
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let record = record(at: indexPath)
        let controller = VillageNBTEditorViewController(record: record, store: store) { [weak self] in
            self?.loadRecords()
            self?.onSave()
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let record = record(at: indexPath)
        let copy = UIContextualAction(style: .normal, title: "复制键") { _, _, completion in
            UIPasteboard.general.string = record.keyText
            completion(true)
        }
        copy.backgroundColor = .systemBlue
        return UISwipeActionsConfiguration(actions: [copy])
    }
}
