import UIKit

/// Read-only, searchable list for Bedrock numeric data values that do not use
/// biome color swatches.
final class BedrockDataValueListViewController: UITableViewController, UISearchResultsUpdating {
    private let searchController = UISearchController(searchResultsController: nil)
    private let allEntries: [BedrockDataValueEntry]
    private var visibleEntries: [BedrockDataValueEntry]

    init(title: String, entries: [BedrockDataValueEntry]) {
        self.allEntries = entries
        self.visibleEntries = entries
        super.init(style: .plain)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜索十进制/十六进制 ID、名称或 identifier"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        tableView.tableFooterView = UIView()
    }

    func updateSearchResults(for searchController: UISearchController) {
        visibleEntries = BedrockDataValueCatalog.search(
            allEntries,
            query: searchController.searchBar.text ?? ""
        )
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visibleEntries.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BedrockDataValue")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "BedrockDataValue")
        let entry = visibleEntries[indexPath.row]
        cell.textLabel?.text = "ID \(entry.id) · \(entry.displayName)"
        cell.detailTextLabel?.text = "\(entry.identifier) · \(entry.hexadecimalID)"
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.imageView?.image = nil
        cell.accessoryType = .none
        cell.selectionStyle = .none
        return cell
    }
}
