import UIKit

/// Searchable numeric-ID/name catalogue used by all biome editors. The list is
/// advisory: custom/unknown UInt32 IDs can still be entered directly.
final class BiomeIDPickerViewController: UITableViewController, UISearchResultsUpdating {
    private let searchController = UISearchController(searchResultsController: nil)
    private var entries = BedrockBiomeCatalog.entries
    private let currentID: UInt32?
    private let selectionEnabled: Bool
    var onSelect: ((UInt32) -> Void)?

    init(currentID: UInt32? = nil, selectionEnabled: Bool = true) {
        self.currentID = currentID
        self.selectionEnabled = selectionEnabled
        super.init(style: .plain)
        title = selectionEnabled ? "选择生物群系" : "生物群系 ID 对照"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜索数字 ID、名称或 identifier"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        if selectionEnabled {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: "输入 ID",
                style: .plain,
                target: self,
                action: #selector(enterCustomID)
            )
        }
    }

    func updateSearchResults(for searchController: UISearchController) {
        entries = BedrockBiomeCatalog.search(searchController.searchBar.text ?? "")
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { entries.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BiomeCatalog")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "BiomeCatalog")
        let entry = entries[indexPath.row]
        cell.textLabel?.text = "ID \(entry.id) · \(entry.displayName)"
        cell.detailTextLabel?.text = entry.identifier
        cell.imageView?.image = swatch(for: entry.id)
        cell.accessoryType = currentID == entry.id ? .checkmark : .none
        cell.selectionStyle = selectionEnabled ? .default : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard selectionEnabled else { return }
        commit(entries[indexPath.row].id)
    }

    @objc private func enterCustomID() {
        let alert = UIAlertController(
            title: "输入生物群系数字 ID",
            message: "支持 0…4294967295；未知或自定义 ID 也可以保存。",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.keyboardType = .numberPad
            field.placeholder = "UInt32 ID"
            if let currentID = self.currentID { field.text = String(currentID) }
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "使用", style: .default) { [weak self, weak alert] _ in
            guard let text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let value = UInt32(text) else {
                self?.showError(MCBEEditorError.malformedData("请输入有效的 UInt32 生物群系 ID"))
                return
            }
            self?.commit(value)
        })
        present(alert, animated: true)
    }

    private func commit(_ value: UInt32) {
        onSelect?(value)
        navigationController?.popViewController(animated: true)
    }

    private func swatch(for id: UInt32) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale
        return UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24), format: format).image { context in
            let rect = CGRect(x: 2, y: 2, width: 20, height: 20)
            BedrockBiomeCatalog.color(for: id).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 5).fill()
            UIColor.white.withAlphaComponent(0.75).setStroke()
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 5)
            path.lineWidth = 1
            path.stroke()
        }
    }
}
