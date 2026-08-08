import UIKit

final class EntityNBTImportReviewViewController: UITableViewController {
    private let session: WorldSession
    private let store: BedrockWorldObjectNBTStore
    private var documents: [NBTDocument]
    private let onComplete: ([BedrockWorldObjectCreateResult]) -> Void
    private let viewedItems = ViewedItemTracker()

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
        "文件中的每个根标签都会创建一个实体。导入准备阶段只修改 Pos 和 UniqueID，不补充任何默认实体标签，也不改动 DimensionId；缺少 DimensionId 的实体会在点击“导入全部”时统一选择写入维度。"
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
        let key = String(indexPath.row)
        ViewedListSupport.configure(
            cell: cell,
            isViewed: viewedItems.contains(key),
            clearAction: { [weak self] in
                guard let self = self else { return }
                ViewedListSupport.presentClearConfirmation(from: self) { [weak self] in
                    guard let self = self else { return }
                    self.viewedItems.clear(key)
                    self.tableView.reloadData()
                }
            }
        )
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        viewedItems.mark(String(indexPath.row))
        tableView.reloadRows(at: [indexPath], with: .none)
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
        let missingDimensionCount = documents.reduce(into: 0) { count, document in
            if BedrockEntityCommonNBT.dimension(in: document.root) == nil { count += 1 }
        }
        guard missingDimensionCount > 0 else {
            performImport(fallbackDimension: nil)
            return
        }

        let alert = UIAlertController(
            title: "选择维度",
            message: "有 \(missingDimensionCount) 个实体缺少 DimensionId。选择这些实体要写入的维度；不会向实体 NBT 中添加 DimensionId 标签。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "主世界", style: .default) { [weak self] _ in
            self?.performImport(fallbackDimension: 0)
        })
        alert.addAction(UIAlertAction(title: "下界", style: .default) { [weak self] _ in
            self?.performImport(fallbackDimension: 1)
        })
        alert.addAction(UIAlertAction(title: "末地", style: .default) { [weak self] _ in
            self?.performImport(fallbackDimension: 2)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func performImport(fallbackDimension: Int32?) {
        navigationItem.rightBarButtonItem?.isEnabled = false
        do {
            var results = [BedrockWorldObjectCreateResult]()
            for document in documents {
                results.append(try store.createEntity(from: document, fallbackDimension: fallbackDimension))
            }
            session.notifyAfterDatabaseMutation()
            onComplete(results)
        } catch {
            navigationItem.rightBarButtonItem?.isEnabled = true
            showError(error, title: "导入实体失败")
        }
    }
}
