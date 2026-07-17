import UIKit

final class WorldToolsViewController: UITableViewController {
    private let session: WorldSession
    private let inspector = WorldInspector()
    private let importer = WorldImportService()
    private var infoRows: [WorldInfoRow] = []
    private var isLoading = false

    init(session: WorldSession) {
        self.session = session
        super.init(style: .insetGrouped)
        title = "信息"
        tabBarItem = UITabBarItem(title: "信息", image: UIImage(systemName: "info.circle"), tag: 3)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(reloadData))
        NotificationCenter.default.addObserver(self, selector: #selector(worldDidChange), name: WorldSession.worldDidChangeNotification, object: session)
        reloadData()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func worldDidChange() { reloadData() }

    @objc private func reloadData() {
        guard !isLoading else { return }
        isLoading = true
        let overlay = showBusy("读取世界信息…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let info = try self.inspector.inspect(session: self.session)
                DispatchQueue.main.async { overlay.removeFromSuperview(); self.isLoading = false; self.infoRows = info; self.tableView.reloadData() }
            } catch {
                DispatchQueue.main.async { overlay.removeFromSuperview(); self.isLoading = false; self.showError(error, title: "读取世界信息失败") }
            }
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 5 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return infoRows.count
        case 1: return 4
        case 2, 3, 4: return 1
        default: return 0
        }
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "世界信息"
        case 1: return "基岩版数据值"
        case 2: return "世界编辑"
        case 3: return "数据工具"
        case 4: return "世界文件"
        default: return nil
        }
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 4 ? "使用修改功能前请自行导出世界。" : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "InfoCell") ?? UITableViewCell(style: .value1, reuseIdentifier: "InfoCell")
            let row = infoRows[indexPath.row]
            cell.textLabel?.text = row.title
            cell.detailTextLabel?.text = row.value
            cell.detailTextLabel?.numberOfLines = 2
            cell.selectionStyle = .none
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "ActionCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "ActionCell")
        cell.textLabel?.text = nil
        cell.detailTextLabel?.text = nil
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.imageView?.image = nil
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default

        switch indexPath.section {
        case 1:
            let rows: [(String, String)] = [
                ("实体ID", "实体短数字 ID、identifier 与十六进制值"),
                ("生物群系ID", "生物群系数字 ID、名称与颜色图标"),
                ("状态效果ID", "状态效果数字 ID、名称与十六进制值"),
                ("魔咒ID", "魔咒数字 ID、名称与十六进制值")
            ]
            cell.textLabel?.text = rows[indexPath.row].0
            cell.detailTextLabel?.text = rows[indexPath.row].1
        case 2:
            cell.textLabel?.text = "天气"
            cell.detailTextLabel?.text = "查看并修改降雨、雷暴等级与持续时间"
            cell.imageView?.image = UIImage(systemName: "cloud.rain")
        case 3:
            cell.textLabel?.text = "数据库浏览器"
            cell.detailTextLabel?.text = "查看、搜索和导出 LevelDB 原始键值"
            cell.imageView?.image = UIImage(systemName: "cylinder")
        case 4:
            cell.textLabel?.text = "导出当前世界 (.mcworld)"
            cell.detailTextLabel?.text = "手动保存一份可重新导入的世界文件"
            cell.imageView?.image = UIImage(systemName: "square.and.arrow.up")
        default:
            break
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch indexPath.section {
        case 1:
            showBedrockDataValues(row: indexPath.row)
        case 2:
            navigationController?.pushViewController(WeatherEditorViewController(session: session), animated: true)
        case 3:
            navigationController?.pushViewController(DatabaseBrowserViewController(session: session), animated: true)
        case 4:
            exportCurrentWorld()
        default:
            break
        }
    }

    private func showBedrockDataValues(row: Int) {
        let controller: UIViewController
        switch row {
        case 0:
            controller = BedrockDataValueListViewController(title: "实体 ID", entries: BedrockDataValueCatalog.entities)
        case 1:
            controller = BiomeIDPickerViewController(selectionEnabled: false)
        case 2:
            controller = BedrockDataValueListViewController(title: "状态效果 ID", entries: BedrockDataValueCatalog.statusEffects)
        case 3:
            controller = BedrockDataValueListViewController(title: "魔咒 ID", entries: BedrockDataValueCatalog.enchantments)
        default:
            return
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    private func exportCurrentWorld() {
        let overlay = showBusy("创建 .mcworld…")
        session.close()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let url = try self.importer.exportWorld(self.session.world)
                DispatchQueue.main.async { overlay.removeFromSuperview(); self.share(url, source: self.view) }
            } catch { DispatchQueue.main.async { overlay.removeFromSuperview(); self.showError(error, title: "导出失败") } }
        }
    }
    private func share(_ url: URL, source: UIView) {
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = source
        activity.popoverPresentationController?.sourceRect = CGRect(x: source.bounds.midX, y: source.bounds.midY, width: 1, height: 1)
        present(activity, animated: true)
    }
}
