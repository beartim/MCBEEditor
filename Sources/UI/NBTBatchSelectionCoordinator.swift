import UIKit

protocol NBTBatchTreeSelectionDelegate: AnyObject {
    var nbtBatchRows: [NBTNode] { get }
    var nbtBatchRoot: NBTValue { get set }
    var nbtBatchNavigationItem: UINavigationItem { get }
    var nbtBatchTableView: UITableView { get }
    var nbtBatchPresenter: UIViewController { get }
    var nbtBatchExportBaseFilename: String { get }

    func restoreNBTNavigationItems()
    func nbtBatchSelectionDidMutate()
    func nbtBatchCanDelete(_ node: NBTNode) -> Bool
}

extension NBTBatchTreeSelectionDelegate {
    var nbtBatchExportBaseFilename: String { nbtBatchPresenter.title ?? "nbt-selection" }
    func nbtBatchCanDelete(_ node: NBTNode) -> Bool { !node.path.isEmpty }
}

/// Shared batch-selection behavior for the editable NBT tree screens.
/// Selection is path-based so rebuilding or filtering the visible rows does not
/// accidentally target a different tag.
final class NBTBatchSelectionCoordinator: NSObject {
    private weak var delegate: NBTBatchTreeSelectionDelegate?
    private(set) var isActive = false
    private var selectedPaths = Set<[NBTPathComponent]>()

    init(delegate: NBTBatchTreeSelectionDelegate) {
        self.delegate = delegate
        super.init()
    }

    var selectionButton: UIBarButtonItem {
        UIBarButtonItem(title: "选择", style: .plain, target: self, action: #selector(beginSelection))
    }

    func contains(_ path: [NBTPathComponent]) -> Bool {
        selectedPaths.contains(path)
    }

    func synchronizeWithVisibleRows() {
        guard isActive, let delegate = delegate else { return }
        let visible = Set(delegate.nbtBatchRows.map(\.path))
        selectedPaths.formIntersection(visible)
        refreshNavigationItems()
    }

    func configureCell(_ cell: UITableViewCell, node: NBTNode, normalAccessory: UITableViewCell.AccessoryType) {
        if isActive {
            cell.accessoryType = selectedPaths.contains(node.path) ? .checkmark : .none
            cell.selectionStyle = .default
        } else {
            cell.accessoryType = normalAccessory
            cell.selectionStyle = .default
        }
    }

    /// Returns true when the tap was consumed by batch selection.
    func handleTap(on node: NBTNode) -> Bool {
        guard isActive else { return false }
        if selectedPaths.contains(node.path) {
            selectedPaths.remove(node.path)
        } else {
            selectedPaths.insert(node.path)
        }
        delegate?.nbtBatchTableView.reloadData()
        refreshNavigationItems()
        return true
    }

    @objc private func beginSelection() {
        guard let delegate = delegate, !delegate.nbtBatchRows.isEmpty else { return }
        isActive = true
        selectedPaths.removeAll()
        delegate.nbtBatchTableView.reloadData()
        refreshNavigationItems()
    }

    @objc private func cancelSelection() {
        isActive = false
        selectedPaths.removeAll()
        delegate?.nbtBatchTableView.reloadData()
        delegate?.restoreNBTNavigationItems()
    }

    @objc private func toggleSelectAll() {
        guard let delegate = delegate else { return }
        let visiblePaths = Set(delegate.nbtBatchRows.map(\.path))
        if !visiblePaths.isEmpty, visiblePaths.isSubset(of: selectedPaths) {
            selectedPaths.subtract(visiblePaths)
        } else {
            selectedPaths.formUnion(visiblePaths)
        }
        delegate.nbtBatchTableView.reloadData()
        refreshNavigationItems()
    }

    @objc private func copySelected() {
        guard let delegate = delegate else { return }
        let nodes = selectedNodes(in: delegate.nbtBatchRows)
        guard !nodes.isEmpty else { return }
        NBTEditingUI.copyTags(nodes, from: delegate.nbtBatchPresenter)
        refreshNavigationItems(message: "已复制 \(nodes.count) 个 NBT 标签")
    }

    @objc private func exportSelected() {
        guard let delegate = delegate else { return }
        let nodes = selectedNodes(in: delegate.nbtBatchRows)
        guard !nodes.isEmpty else { return }
        NBTExportUI.presentFormatChooser(
            from: delegate.nbtBatchPresenter,
            documents: NBTExportUI.documents(from: nodes),
            baseFilename: delegate.nbtBatchExportBaseFilename + "-selected",
            allowMCStructure: nodes.count == 1,
            barButtonItem: delegate.nbtBatchNavigationItem.rightBarButtonItems?.first
        )
    }

    @objc private func deleteSelected() {
        guard let delegate = delegate else { return }
        let selected = selectedNodes(in: delegate.nbtBatchRows)
        guard !selected.isEmpty else { return }
        let protected = selected.filter { !delegate.nbtBatchCanDelete($0) }
        guard protected.isEmpty else {
            delegate.nbtBatchPresenter.showError(
                BlocktopographError.unsupported("所选内容包含 NBT 根节点或受保护标签，不能批量删除。"),
                title: "无法批量删除"
            )
            return
        }
        let nodes = normalizedDeletionNodes(from: selected)
        guard !nodes.isEmpty else { return }

        let alert = UIAlertController(
            title: "删除所选 NBT 标签？",
            message: "将删除 \(nodes.count) 个标签及其全部子标签。该修改仍需使用当前编辑器的保存按钮写回。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self, weak delegate] _ in
            guard let self = self, let delegate = delegate else { return }
            do {
                delegate.nbtBatchRoot = try NBTTreeMutation.deleting(
                    at: nodes.map(\.path),
                    in: delegate.nbtBatchRoot
                )
                self.selectedPaths.removeAll()
                delegate.nbtBatchSelectionDidMutate()
                self.synchronizeWithVisibleRows()
                delegate.nbtBatchTableView.reloadData()
                self.refreshNavigationItems(message: "已删除 \(nodes.count) 个 NBT 标签")
            } catch {
                delegate.nbtBatchPresenter.showError(error, title: "批量删除失败")
            }
        })
        delegate.nbtBatchPresenter.present(alert, animated: true)
    }

    private func selectedNodes(in rows: [NBTNode]) -> [NBTNode] {
        rows.filter { selectedPaths.contains($0.path) }
    }

    private func normalizedDeletionNodes(from selected: [NBTNode]) -> [NBTNode] {
        let normalizedPaths = Set(NBTTreeMutation.normalizedDeletionPaths(selected.map(\.path)))
        return selected.filter { normalizedPaths.contains($0.path) }
    }

    private func refreshNavigationItems(message: String? = nil) {
        guard isActive, let delegate = delegate else { return }
        let visiblePaths = Set(delegate.nbtBatchRows.map(\.path))
        let allVisibleSelected = !visiblePaths.isEmpty && visiblePaths.isSubset(of: selectedPaths)

        let cancel = UIBarButtonItem(title: "取消", style: .plain, target: self, action: #selector(cancelSelection))
        let selectAll = UIBarButtonItem(
            title: allVisibleSelected ? "取消全选" : "全选",
            style: .plain,
            target: self,
            action: #selector(toggleSelectAll)
        )
        let export = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(exportSelected))
        export.accessibilityLabel = "导出所选 NBT 标签"
        let copy = UIBarButtonItem(title: "复制", style: .plain, target: self, action: #selector(copySelected))
        let delete = UIBarButtonItem(title: "删除", style: .plain, target: self, action: #selector(deleteSelected))
        delete.tintColor = .systemRed
        export.isEnabled = !selectedPaths.isEmpty
        copy.isEnabled = !selectedPaths.isEmpty
        delete.isEnabled = !selectedPaths.isEmpty
        delegate.nbtBatchNavigationItem.rightBarButtonItems = [delete, copy, export, selectAll, cancel]
        delegate.nbtBatchNavigationItem.prompt = message ?? "批量选择：已选择 \(selectedPaths.count) 个标签"
    }
}
