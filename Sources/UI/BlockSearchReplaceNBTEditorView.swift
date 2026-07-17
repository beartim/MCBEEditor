import UIKit

enum BlockSearchReplaceEditorMode {
    case search
    case replacement
}

/// Compact NBT-style editor used by the chunk search/replace screen.
/// Each instance represents one block storage layer and exposes a `name`
/// string plus a `states` Compound. Search values are interpreted as partial
/// text matches; replacement values preserve the selected NBT scalar type.
final class BlockSearchReplaceNBTEditorView: UIView, UITableViewDataSource, UITableViewDelegate {
    let layerIndex: Int
    let mode: BlockSearchReplaceEditorMode

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let addButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private var nameText = ""
    private var stateTags = [NBTNamedTag]()
    var onContentChanged: (() -> Void)?

    init(layerIndex: Int, mode: BlockSearchReplaceEditorMode) {
        self.layerIndex = layerIndex
        self.mode = mode
        super.init(frame: .zero)
        configureUI()
        updateStatus()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var hasContent: Bool {
        !nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !stateTags.isEmpty
    }

    var explicitBlockName: String? {
        let value = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func makeSearchCriteria(layers: Set<Int>? = nil) -> BedrockBlockSearchCriteria? {
        guard mode == .search, hasContent else { return nil }
        let cleanName = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let criteria = stateTags.map { tag -> BedrockBlockStateCriterion in
            let valueText = tag.value.editableText ?? tag.value.summary
            let cleanValue = valueText.trimmingCharacters(in: .whitespacesAndNewlines)
            return BedrockBlockStateCriterion(
                keyContains: tag.name,
                valueContains: cleanValue.isEmpty ? nil : cleanValue
            )
        }
        return BedrockBlockSearchCriteria(
            nameContains: cleanName.isEmpty ? nil : cleanName,
            stateCriteria: criteria,
            layers: layers ?? Set([layerIndex])
        )
    }

    func makeReplacement() -> BedrockBlockReplacement {
        let cleanName = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let assignments = Dictionary(uniqueKeysWithValues: stateTags.map { ($0.name, $0.value) })
        return BedrockBlockReplacement(
            name: cleanName.isEmpty ? nil : cleanName,
            typedStateAssignments: assignments,
            replaceAllStates: true
        )
    }

    private func configureUI() {
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 10
        layer.borderColor = UIColor.separator.cgColor
        layer.borderWidth = 1 / UIScreen.main.scale
        clipsToBounds = true

        let header = UILabel()
        header.text = "层 \(layerIndex)"
        header.font = .preferredFont(forTextStyle: .headline)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 48
        tableView.backgroundColor = .tertiarySystemGroupedBackground
        tableView.tableFooterView = UIView()
        tableView.layer.cornerRadius = 8
        tableView.clipsToBounds = true

        addButton.setTitle("增加 NBT 标签", for: .normal)
        addButton.setTitleColor(.systemBlue, for: .normal)
        addButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        addButton.addTarget(self, action: #selector(addStateTag), for: .touchUpInside)
        addButton.heightAnchor.constraint(equalToConstant: 32).isActive = true

        statusLabel.font = .preferredFont(forTextStyle: .caption2)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 2

        let stack = UIStackView(arrangedSubviews: [header, tableView, addButton, statusLabel])
        stack.axis = .vertical
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            tableView.heightAnchor.constraint(equalToConstant: 190)
        ])
    }

    private func updateStatus() {
        switch mode {
        case .search:
            statusLabel.text = hasContent
                ? "已启用层 \(layerIndex) 搜索；name 和 states 均支持部分匹配。"
                : "未填写时，层 \(layerIndex) 不参与搜索。"
        case .replacement:
            if !isUserInteractionEnabled {
                statusLabel.text = "“是否改变层 1”关闭；该列不会写入。"
            } else {
                statusLabel.text = hasContent
                    ? "保存时先清空原 states，再写入上方标签。"
                    : (layerIndex == 1 ? "留空表示删除匹配位置的原层 1。" : "留空表示保持 name，并将 states 清空。")
            }
        }
    }

    func setEditorEnabled(_ enabled: Bool) {
        isUserInteractionEnabled = enabled
        alpha = enabled ? 1 : 0.42
        addButton.isEnabled = enabled
        tableView.isScrollEnabled = enabled
        updateStatus()
    }

    private func reload() {
        tableView.reloadData()
        updateStatus()
        onContentChanged?()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        2 + stateTags.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.detailTextLabel?.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.imageView?.contentMode = .scaleAspectFit

        if indexPath.row == 0 {
            cell.imageView?.image = NBTTagIcon.image(for: .string)
            cell.textLabel?.text = "name"
            let clean = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
            cell.detailTextLabel?.text = clean.isEmpty
                ? (mode == .search ? "String · 留空不匹配 name" : "String · 留空保持原 name")
                : "String · \(clean)"
            cell.accessoryType = .disclosureIndicator
        } else if indexPath.row == 1 {
            cell.imageView?.image = NBTTagIcon.image(for: .compound)
            cell.textLabel?.text = "states"
            cell.detailTextLabel?.text = "Compound{\(stateTags.count)}"
            cell.selectionStyle = .none
        } else {
            let tag = stateTags[indexPath.row - 2]
            cell.imageView?.image = NBTTagIcon.image(for: tag.value.type)
            cell.textLabel?.text = tag.name
            let detail = tag.value.editableText ?? tag.value.summary
            cell.detailTextLabel?.text = "\(tag.value.type.displayName) · \(detail)"
            cell.indentationLevel = 1
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.row == 0 {
            editName()
        } else if indexPath.row >= 2 {
            editState(at: indexPath.row - 2)
        }
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard indexPath.row >= 2 else { return nil }
        let index = indexPath.row - 2
        let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, done in
            guard let self = self, self.stateTags.indices.contains(index) else { done(false); return }
            self.stateTags.remove(at: index)
            self.reload()
            done(true)
        }
        let rename = UIContextualAction(style: .normal, title: "重命名") { [weak self] _, _, done in
            self?.renameState(at: index)
            done(true)
        }
        rename.backgroundColor = .systemOrange
        return UISwipeActionsConfiguration(actions: [delete, rename])
    }

    private func editName() {
        guard let presenter = owningViewController else { return }
        let alert = UIAlertController(
            title: mode == .search ? "搜索 name" : "替换 name",
            message: mode == .search ? "支持不区分大小写的部分匹配。" : "留空时保持原方块 name。",
            preferredStyle: .alert
        )
        alert.addTextField { [nameText] field in
            field.text = nameText
            field.placeholder = self.mode == .search ? "例如 stone" : "例如 minecraft:stone"
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self, weak alert] _ in
            self?.nameText = alert?.textFields?.first?.text ?? ""
            self?.reload()
        })
        presenter.present(alert, animated: true)
    }

    @objc private func addStateTag() {
        guard let presenter = owningViewController else { return }
        let allowed: [NBTTagType] = [.byte, .short, .int, .long, .float, .double, .string]
        let sheet = UIAlertController(title: "增加 states NBT 标签", message: "选择值类型", preferredStyle: .actionSheet)
        for type in allowed {
            sheet.addAction(UIAlertAction(title: type.displayName, style: .default) { [weak self] _ in
                self?.presentAddInput(type: type)
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = addButton
            popover.sourceRect = addButton.bounds
        }
        presenter.present(sheet, animated: true)
    }

    private func presentAddInput(type: NBTTagType) {
        guard let presenter = owningViewController else { return }
        let alert = UIAlertController(
            title: "增加 \(type.displayName)",
            message: mode == .search ? "标签名和值都按部分参数搜索；String 值可留空，仅检查标签存在。" : "该标签会写入新的 states Compound。",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "NBT 标签名称"
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addTextField { field in
            field.placeholder = type == .string ? "值（可留空）" : "值"
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            if type != .string { field.keyboardType = .numbersAndPunctuation }
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "增加", style: .default) { [weak self, weak presenter, weak alert] _ in
            guard let self = self, let presenter = presenter else { return }
            do {
                let name = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { throw BlocktopographError.malformedData("NBT 标签名称不能为空") }
                guard !self.stateTags.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                    throw BlocktopographError.malformedData("states 已存在标签：\(name)")
                }
                let raw = alert?.textFields?.last?.text ?? ""
                let value = try NBTTreeMutation.parseInitialValue(raw, type: type)
                self.stateTags.append(NBTNamedTag(name: name, value: value))
                self.stateTags.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                self.reload()
            } catch {
                presenter.showError(error, title: "无法增加 states 标签")
            }
        })
        presenter.present(alert, animated: true)
    }

    private func editState(at index: Int) {
        guard stateTags.indices.contains(index), let presenter = owningViewController else { return }
        let tag = stateTags[index]
        let node = NBTNode(path: [.compound("states"), .compound(tag.name)], name: tag.name, value: tag.value, depth: 1)
        NBTEditingUI.presentEdit(from: presenter, node: node) { [weak self] replacement in
            guard let self = self, self.stateTags.indices.contains(index) else { return }
            self.stateTags[index].value = replacement
            self.reload()
        }
    }

    private func renameState(at index: Int) {
        guard stateTags.indices.contains(index), let presenter = owningViewController else { return }
        let current = stateTags[index].name
        NBTEditingUI.presentRename(from: presenter, currentName: current) { [weak self, weak presenter] newName in
            guard let self = self, let presenter = presenter, self.stateTags.indices.contains(index) else { return }
            let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else {
                presenter.showError(BlocktopographError.malformedData("NBT 标签名称不能为空"), title: "重命名失败")
                return
            }
            guard current.caseInsensitiveCompare(clean) == .orderedSame || !self.stateTags.contains(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) else {
                presenter.showError(BlocktopographError.malformedData("states 已存在标签：\(clean)"), title: "重命名失败")
                return
            }
            self.stateTags[index].name = clean
            self.stateTags.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            self.reload()
        }
    }

    private var owningViewController: UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }
}
