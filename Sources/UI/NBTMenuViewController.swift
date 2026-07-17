import UIKit

final class NBTMenuViewController: UITableViewController, UISearchResultsUpdating {
    private let session: WorldSession

    private struct Item {
        let title: String
        let subtitle: String
        let icon: String
        let fallback: String
    }

    private let searchController = UISearchController(searchResultsController: nil)
    private var allDatabaseKeys = [Data]()
    private var filteredDatabaseKeys = [Data]()
    private var isLoadingKeys = false

    private let items = [
        Item(title: "世界 NBT", subtitle: "查看和修改 level.dat 世界设置", icon: "globe", fallback: "世"),
        Item(title: "玩家 NBT", subtitle: "查看和修改本机、远程及服务器玩家数据", icon: "person.crop.circle", fallback: "玩"),
        Item(title: "村庄 NBT", subtitle: "按村庄分别查看和修改 mVillages 与 VILLAGE_* 参数", icon: "house.fill", fallback: "村"),
        Item(title: "结构 NBT", subtitle: "查看和修改结构方块保存的结构模板", icon: "square.stack.3d.up", fallback: "构"),
        Item(title: "元数据", subtitle: "查看和修改世界级 data NBT、地图、计分板与计划刻", icon: "tray.full.fill", fallback: "元")
    ]

    init(session: WorldSession) {
        self.session = session
        super.init(style: .insetGrouped)
        title = "NBT"
        tabBarItem = UITabBarItem(title: "NBT", image: UIImage(systemName: "list.bullet.indent"), tag: 2)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.rowHeight = 72
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜索 NBT / LevelDB 键"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        loadDatabaseKeys()
    }

    private var keySearchQuery: String {
        searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private var isSearchingKeys: Bool { !keySearchQuery.isEmpty }

    private func loadDatabaseKeys() {
        guard !isLoadingKeys else { return }
        isLoadingKeys = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let keys = (try? self.session.database().entries(includeValues: false, limit: 0).map(\.key)) ?? []
            DispatchQueue.main.async {
                self.isLoadingKeys = false
                self.allDatabaseKeys = keys
                self.applyKeyFilter()
            }
        }
    }

    func updateSearchResults(for searchController: UISearchController) { applyKeyFilter() }

    private func applyKeyFilter() {
        let query = keySearchQuery
        guard !query.isEmpty else {
            filteredDatabaseKeys.removeAll()
            tableView.reloadData()
            navigationItem.prompt = nil
            return
        }
        filteredDatabaseKeys = allDatabaseKeys.filter { key in
            let text = String(data: key, encoding: .utf8)?.replacingOccurrences(of: "\0", with: "\\0").lowercased() ?? ""
            return text.contains(query) || key.hexString.lowercased().contains(query) || (BedrockDBKey.parse(key)?.description.lowercased().contains(query) == true)
        }
        if filteredDatabaseKeys.count > 500 { filteredDatabaseKeys = Array(filteredDatabaseKeys.prefix(500)) }
        navigationItem.prompt = isLoadingKeys ? "正在读取数据库键…" : "找到 \(filteredDatabaseKeys.count) 个键（最多显示 500）"
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { isSearchingKeys ? filteredDatabaseKeys.count : items.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        isSearchingKeys ? "NBT 键搜索结果" : "NBT 数据"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        isSearchingKeys ? "点按键后会尝试按 NBT 解析；可解析记录可修改并写回，其他记录显示原始值。" : "所有可解析的 NBT 均支持修改标量、增加子标签、重命名和删除节点；保存前请先备份世界。"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "NBTMenuCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "NBTMenuCell")
        cell.textLabel?.font = .preferredFont(forTextStyle: .headline)
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 2
        cell.imageView?.contentMode = .scaleAspectFit
        cell.accessoryType = .disclosureIndicator
        if isSearchingKeys {
            let key = filteredDatabaseKeys[indexPath.row]
            let parsed = BedrockDBKey.parse(key)
            let text = String(data: key, encoding: .utf8)?.replacingOccurrences(of: "\0", with: "\\0")
            cell.textLabel?.text = text?.isEmpty == false ? text : "0x\(key.hexString)"
            cell.detailTextLabel?.text = parsed?.description ?? "\(key.count) bytes · 0x\(key.hexString.prefix(80))"
            cell.imageView?.image = UIImage(systemName: "key.fill")
        } else {
            let item = items[indexPath.row]
            cell.textLabel?.text = item.title
            cell.detailTextLabel?.text = item.subtitle
            cell.imageView?.image = menuIcon(systemName: item.icon, fallback: item.fallback)
        }
        return cell
    }

    private func menuIcon(systemName: String, fallback: String) -> UIImage {
        if let image = UIImage(systemName: systemName) {
            return image.withRenderingMode(.alwaysTemplate)
        }
        let size = CGSize(width: 30, height: 30)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.systemBlue.setFill()
            context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let text = NSAttributedString(string: fallback, attributes: attributes)
            let textSize = text.size()
            text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2))
        }.withRenderingMode(.alwaysOriginal)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if isSearchingKeys {
            openDatabaseKey(filteredDatabaseKeys[indexPath.row])
            return
        }
        let controller: UIViewController
        switch indexPath.row {
        case 0:
            controller = NBTTreeViewController(session: session)
        case 1:
            controller = PlayerNBTListViewController(session: session)
        case 2:
            controller = VillageNBTListViewController(session: session)
        case 3:
            controller = StructureNBTListViewController(session: session)
        default:
            controller = MetadataNBTListViewController(session: session)
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    private func openDatabaseKey(_ key: Data) {
        let overlay = showBusy("读取键值并识别 NBT…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                guard let value = try self.session.database().get(key) else {
                    throw BlocktopographError.malformedData("该键没有值或已被删除")
                }
                let record = MetadataNBTStore.makeRecord(key: key, value: value)
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    if record.roots != nil {
                        let controller = MetadataNBTRecordViewController(record: record, store: MetadataNBTStore(session: self.session), onSave: {})
                        self.navigationController?.pushViewController(controller, animated: true)
                    } else {
                        let controller = DatabaseValueViewController(title: record.keyText, data: value, editable: false)
                        controller.navigationItem.prompt = record.decodeError
                        self.navigationController?.pushViewController(controller, animated: true)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.showError(error, title: "读取键值失败")
                }
            }
        }
    }

}
