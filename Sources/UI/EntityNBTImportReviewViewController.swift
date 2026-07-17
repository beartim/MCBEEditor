import UIKit

final class EntityNBTImportReviewViewController: UITableViewController {
    private let session: WorldSession
    private let store: BedrockWorldObjectNBTStore
    private var documents: [NBTDocument]
    private let onComplete: ([BedrockWorldObjectCreateResult]) -> Void

    init(
        session: WorldSession,
        documents: [NBTDocument],
        onComplete: @escaping ([BedrockWorldObjectCreateResult]) -> Void
    ) {
        self.session = session
        self.store = BedrockWorldObjectNBTStore(session: session)
        self.documents = documents
        self.onComplete = onComplete
        super.init(style: .insetGrouped)
        title = "检查实体 NBT"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "导入全部",
            style: .done,
            target: self,
            action: #selector(importAll)
        )
        navigationItem.prompt = "导入前可逐个打开并修改；保存后返回此页"
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { documents.count }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "文件中的每个根标签都会创建一个实体。坐标、维度和 UniqueID 已按选取文件前填写的值写入；后续仍可在此逐项修改。"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let document = documents[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "EntityNBTImportReviewCell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "EntityNBTImportReviewCell")
        let identifier = BedrockEntityCommonNBT.identifier(in: document.root) ?? "未知实体"
        let uniqueID = BedrockEntityCommonNBT.uniqueID(in: document.root).map(String.init) ?? "缺失"
        let position = BedrockEntityCommonNBT.position(in: document.root)
        let positionText = position.map { "\($0.blockX), \($0.blockY), \($0.blockZ)" } ?? "缺失"
        let dimension = BedrockEntityCommonNBT.dimension(in: document.root)
            .map(WorldCommandParser.dimensionName(for:)) ?? "缺失"
        cell.textLabel?.text = "\(indexPath.row + 1). \(identifier)"
        cell.detailTextLabel?.text = "UniqueID \(uniqueID)；\(dimension)；\(positionText)"
        cell.detailTextLabel?.numberOfLines = 2
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let editor = StandaloneNBTEditorViewController(
            document: documents[indexPath.row],
            title: "实体 \(indexPath.row + 1)",
            onCommit: { [weak self] document in
                guard let self = self, self.documents.indices.contains(indexPath.row) else { return }
                self.documents[indexPath.row] = document
                self.tableView.reloadRows(at: [indexPath], with: .automatic)
            }
        )
        navigationController?.pushViewController(editor, animated: true)
    }

    @objc private func importAll() {
        navigationItem.rightBarButtonItem?.isEnabled = false
        do {
            var results = [BedrockWorldObjectCreateResult]()
            for document in documents {
                results.append(try store.createEntity(from: document))
            }
            session.notifyAfterDatabaseMutation()
            onComplete(results)
        } catch {
            navigationItem.rightBarButtonItem?.isEnabled = true
            showError(error, title: "导入实体失败")
        }
    }
}
