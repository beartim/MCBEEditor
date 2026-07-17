import UIKit

enum NBTEditingUI {

    typealias TagInsertionCompletion = (_ name: String?, _ value: NBTValue, _ replacingExisting: Bool) -> Void

    private static let tagPasteboardType = "com.wzn.blocktopograph.nbt-tag"
    private static let batchTagPasteboardType = "com.wzn.blocktopograph.nbt-tags-v1"
    private static let batchMagic = Data("BTNBTB1".utf8)

    static var hasCopiedTag: Bool {
        UIPasteboard.general.data(forPasteboardType: batchTagPasteboardType) != nil ||
        UIPasteboard.general.data(forPasteboardType: tagPasteboardType) != nil
    }

    static func copyTag(_ node: NBTNode, from presenter: UIViewController? = nil) {
        copyTags([node], from: presenter)
    }

    static func copyTags(_ nodes: [NBTNode], from presenter: UIViewController? = nil) {
        let documents = nodes.map { node -> NBTDocument in
            let name: String
            if case .compound(let compoundName)? = node.path.last {
                name = compoundName
            } else {
                name = ""
            }
            return NBTDocument(rootName: name, root: node.value)
        }
        copyDocuments(documents, from: presenter)
    }

    static func copyDocuments(_ documents: [NBTDocument], from presenter: UIViewController? = nil) {
        guard !documents.isEmpty else { return }
        do {
            let encoded = try documents.map { try BedrockNBTCodec.encode($0, encoding: .littleEndian) }
            var batch = Data()
            batch.append(batchMagic)
            appendUInt32(UInt32(encoded.count), to: &batch)
            for item in encoded {
                appendUInt32(UInt32(item.count), to: &batch)
                batch.append(item)
            }
            UIPasteboard.general.setData(batch, forPasteboardType: batchTagPasteboardType)
            UIPasteboard.general.setData(encoded[0], forPasteboardType: tagPasteboardType)
            presenter?.navigationItem.prompt = documents.count == 1
                ? "已复制 NBT 标签"
                : "已复制 \(documents.count) 个 NBT 标签"
        } catch {
            presenter?.showError(error, title: "复制标签失败")
        }
    }

    static func copyText(_ node: NBTNode, from presenter: UIViewController? = nil) {
        guard let text = node.value.scalarClipboardText else { return }
        UIPasteboard.general.string = text
        presenter?.navigationItem.prompt = "已复制文本内容"
    }

    static func clipboardActions(
        from presenter: UIViewController,
        node: NBTNode,
        sourceView: UIView? = nil,
        pasteCompletion: @escaping TagInsertionCompletion
    ) -> [UIAction] {
        var actions = [UIAction]()
        actions.append(UIAction(title: "复制标签", image: UIImage(systemName: "doc.on.doc")) { _ in
            copyTag(node, from: presenter)
        })
        if node.value.scalarClipboardText != nil {
            actions.append(UIAction(title: "复制文本内容", image: UIImage(systemName: "text.badge.plus")) { _ in
                copyText(node, from: presenter)
            })
        }
        if node.value.isPasteContainer, hasCopiedTag {
            actions.append(UIAction(title: "粘贴标签到此处", image: UIImage(systemName: "doc.on.clipboard")) { _ in
                presentPaste(from: presenter, container: node.value, sourceView: sourceView, completion: pasteCompletion)
            })
        }
        return actions
    }

    static func presentAddOrPaste(
        from presenter: UIViewController,
        container: NBTValue,
        sourceView: UIView? = nil,
        completion: @escaping TagInsertionCompletion
    ) {
        guard hasCopiedTag else {
            presentAdd(from: presenter, container: container, sourceView: sourceView) { name, value in
                completion(name, value, false)
            }
            return
        }
        let sheet = UIAlertController(title: "增加 NBT 标签", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "新建标签", style: .default) { _ in
            presentAdd(from: presenter, container: container, sourceView: sourceView) { name, value in
                completion(name, value, false)
            }
        })
        sheet.addAction(UIAlertAction(title: "粘贴已复制标签", style: .default) { _ in
            presentPaste(from: presenter, container: container, sourceView: sourceView, completion: completion)
        })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        configurePopover(sheet, sourceView: sourceView ?? presenter.view)
        presenter.present(sheet, animated: true)
    }

    static func presentPaste(
        from presenter: UIViewController,
        container: NBTValue,
        sourceView: UIView? = nil,
        completion: @escaping TagInsertionCompletion
    ) {
        do {
            let copied = try copiedTags()
            guard !copied.isEmpty else {
                throw BlocktopographError.malformedData("剪贴板中没有 Blocktopograph NBT 标签")
            }
            switch container {
            case .compound(let existing):
                let existingNames = Set(existing.map(\.name))
                let prepared = preparedCompoundTags(copied, existingNames: existingNames)
                var observedNames = existingNames
                var conflictNames = Set<String>()
                for item in prepared {
                    if observedNames.contains(item.name) { conflictNames.insert(item.name) }
                    observedNames.insert(item.name)
                }

                let applyPaste: (_ overwrite: Bool) -> Void = { overwrite in
                    var occupiedNames = existingNames
                    var pastedCount = 0
                    for item in prepared {
                        let conflicts = occupiedNames.contains(item.name)
                        if conflicts, !overwrite { continue }
                        completion(item.name, item.value, overwrite && conflicts)
                        occupiedNames.insert(item.name)
                        pastedCount += 1
                    }
                    if conflictNames.isEmpty {
                        presenter.navigationItem.prompt = pastedCount == 1
                            ? "已粘贴 NBT 标签"
                            : "已粘贴 \(pastedCount) 个 NBT 标签"
                    } else if overwrite {
                        presenter.navigationItem.prompt = "已粘贴 \(pastedCount) 个标签并覆盖同名标签"
                    } else {
                        presenter.navigationItem.prompt = "已粘贴 \(pastedCount) 个标签；同名标签已保留"
                    }
                }

                guard !conflictNames.isEmpty else {
                    applyPaste(false)
                    return
                }
                let names = conflictNames.sorted()
                let shown = names.prefix(8).joined(separator: "、")
                let suffix = names.count > 8 ? " 等 \(names.count) 个" : ""
                let alert = UIAlertController(
                    title: "存在同名标签",
                    message: "同级 Compound 中已存在：\(shown)\(suffix)。请选择覆盖已有标签，或保留已有标签并跳过冲突项。",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "取消", style: .cancel))
                alert.addAction(UIAlertAction(title: "保留", style: .default) { _ in applyPaste(false) })
                alert.addAction(UIAlertAction(title: "覆盖", style: .destructive) { _ in applyPaste(true) })
                presenter.present(alert, animated: true)

            case .list(let elementType, let values):
                let expectedType: NBTTagType
                if elementType == .end, values.isEmpty {
                    expectedType = copied[0].value.type
                } else {
                    expectedType = elementType
                }
                guard copied.allSatisfy({ $0.value.type == expectedType }) else {
                    let copiedTypes = Set(copied.map { $0.value.type.displayName }).sorted().joined(separator: "、")
                    throw BlocktopographError.malformedData(
                        "该 List 只能粘贴 \(expectedType.displayName)，复制标签包含：\(copiedTypes)"
                    )
                }
                for item in copied { completion(nil, item.value, false) }
                presenter.navigationItem.prompt = copied.count == 1 ? "已粘贴 NBT 标签" : "已粘贴 \(copied.count) 个 NBT 标签"
            default:
                throw BlocktopographError.unsupported("只能向 Compound 或 List 粘贴标签")
            }
        } catch {
            presenter.showError(error, title: "粘贴标签失败")
        }
    }

    private static func preparedCompoundTags(
        _ copied: [(name: String, value: NBTValue)],
        existingNames: Set<String>
    ) -> [(name: String, value: NBTValue)] {
        var generatedNames = existingNames
        return copied.map { item in
            let trimmed = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty else { return (trimmed, item.value) }
            let name = uniqueName(base: "复制的标签", usedNames: &generatedNames)
            return (name, item.value)
        }
    }

    private static func copiedTags() throws -> [(name: String, value: NBTValue)] {
        if let batch = UIPasteboard.general.data(forPasteboardType: batchTagPasteboardType),
           batch.starts(with: batchMagic) {
            var offset = batchMagic.count
            let count = try readUInt32(from: batch, offset: &offset)
            var values = [(name: String, value: NBTValue)]()
            values.reserveCapacity(Int(count))
            for _ in 0..<count {
                let length = try readUInt32(from: batch, offset: &offset)
                guard offset + Int(length) <= batch.count else {
                    throw BlocktopographError.malformedData("批量 NBT 剪贴板数据长度无效")
                }
                let item = batch.subdata(in: offset..<(offset + Int(length)))
                offset += Int(length)
                let document = try BedrockNBTCodec.decode(item, encoding: .littleEndian)
                values.append((document.rootName, document.root))
            }
            return values
        }
        guard let data = UIPasteboard.general.data(forPasteboardType: tagPasteboardType) else {
            throw BlocktopographError.malformedData("剪贴板中没有 Blocktopograph NBT 标签")
        }
        let document = try BedrockNBTCodec.decode(data, encoding: .littleEndian)
        return [(document.rootName, document.root)]
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    private static func readUInt32(from data: Data, offset: inout Int) throws -> UInt32 {
        guard offset + 4 <= data.count else {
            throw BlocktopographError.malformedData("批量 NBT 剪贴板数据不完整")
        }
        let value = data[offset..<(offset + 4)].enumerated().reduce(UInt32(0)) { result, pair in
            result | (UInt32(pair.element) << UInt32(pair.offset * 8))
        }
        offset += 4
        return value
    }

    private static func uniqueName(base: String, usedNames: inout Set<String>) -> String {
        if !usedNames.contains(base) {
            usedNames.insert(base)
            return base
        }
        var suffix = 2
        while usedNames.contains("\(base) \(suffix)") { suffix += 1 }
        let value = "\(base) \(suffix)"
        usedNames.insert(value)
        return value
    }

    private static let creatableTypes: [NBTTagType] = [
        .byte, .short, .int, .long, .float, .double,
        .string, .byteArray, .intArray, .longArray, .list, .compound
    ]

    static func presentCreateRoot(
        from presenter: UIViewController,
        sourceView: UIView? = nil,
        completion: @escaping (NBTDocument) -> Void
    ) {
        let sheet = UIAlertController(
            title: "新建 NBT 根标签",
            message: "选择根标签类型；根名称可以为空。",
            preferredStyle: .actionSheet
        )
        for type in creatableTypes {
            sheet.addAction(UIAlertAction(title: type.displayName, style: .default) { _ in
                let finish: (String?, NBTValue) -> Void = { name, value in
                    completion(NBTDocument(rootName: name ?? "", root: value))
                }
                if type == .list {
                    presentListTypePicker(from: presenter, sourceView: sourceView) { listType in
                        presentInput(
                            from: presenter,
                            type: .list,
                            listElementType: listType,
                            requiresName: true,
                            completion: finish
                        )
                    }
                } else {
                    presentInput(
                        from: presenter,
                        type: type,
                        listElementType: nil,
                        requiresName: true,
                        completion: finish
                    )
                }
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        configurePopover(sheet, sourceView: sourceView ?? presenter.view)
        presenter.present(sheet, animated: true)
    }

    static func presentAdd(
        from presenter: UIViewController,
        container: NBTValue,
        sourceView: UIView? = nil,
        completion: @escaping (_ name: String?, _ value: NBTValue) -> Void
    ) {
        switch container {
        case .compound:
            let sheet = UIAlertController(title: "增加 NBT 标签", message: "选择新标签类型", preferredStyle: .actionSheet)
            for type in creatableTypes {
                sheet.addAction(UIAlertAction(title: type.displayName, style: .default) { _ in
                    if type == .list {
                        presentListTypePicker(from: presenter, sourceView: sourceView) { listType in
                            presentInput(from: presenter, type: type, listElementType: listType, requiresName: true, completion: completion)
                        }
                    } else {
                        presentInput(from: presenter, type: type, listElementType: nil, requiresName: true, completion: completion)
                    }
                })
            }
            sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
            configurePopover(sheet, sourceView: sourceView ?? presenter.view)
            presenter.present(sheet, animated: true)
        case .list(let elementType, _):
            if elementType == .end {
                let sheet = UIAlertController(title: "空 List 元素类型", message: "首次增加元素时确定 List 类型", preferredStyle: .actionSheet)
                for type in creatableTypes {
                    sheet.addAction(UIAlertAction(title: type.displayName, style: .default) { _ in
                        if type == .list {
                            presentListTypePicker(from: presenter, sourceView: sourceView) { nestedType in
                                presentInput(from: presenter, type: .list, listElementType: nestedType, requiresName: false, completion: completion)
                            }
                        } else {
                            presentInput(from: presenter, type: type, listElementType: nil, requiresName: false, completion: completion)
                        }
                    })
                }
                sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
                configurePopover(sheet, sourceView: sourceView ?? presenter.view)
                presenter.present(sheet, animated: true)
            } else {
                presentInput(from: presenter, type: elementType, listElementType: nil, requiresName: false, completion: completion)
            }
        default:
            presenter.showError(BlocktopographError.unsupported("只能向 Compound 或 List 增加节点"), title: "无法增加")
        }
    }

    static func presentEdit(
        from presenter: UIViewController,
        node: NBTNode,
        completion: @escaping (NBTValue) -> Void
    ) {
        guard let initialText = node.value.editableText else {
            presenter.showError(
                BlocktopographError.unsupported("Compound 和 List 请通过增加、删除或编辑子节点修改。"),
                title: "无法直接修改"
            )
            return
        }

        let message: String
        switch node.value {
        case .byteArray, .intArray, .longArray:
            message = "\(node.pathDescription)\n数组元素使用逗号、空格或分号分隔。"
        default:
            message = "\(node.pathDescription)\n\(node.value.type.displayName)"
        }
        let alert = UIAlertController(title: "修改 \(node.name)", message: message, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = initialText
            field.clearButtonMode = .whileEditing
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            if node.value.type != .string { field.keyboardType = .numbersAndPunctuation }
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "修改", style: .default) { [weak presenter, weak alert] _ in
            guard let presenter = presenter else { return }
            do {
                let text = alert?.textFields?.first?.text ?? ""
                let replacement = try NBTTreeMutation.parseInitialValue(text, type: node.value.type)
                completion(replacement)
            } catch {
                presenter.showError(error, title: "修改失败")
            }
        })
        presenter.present(alert, animated: true)
    }

    static func presentRename(
        from presenter: UIViewController,
        currentName: String,
        completion: @escaping (String) -> Void
    ) {
        let alert = UIAlertController(title: "重命名 NBT 标签", message: currentName, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = currentName
            field.clearButtonMode = .whileEditing
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "重命名", style: .default) { [weak alert] _ in
            completion(alert?.textFields?.first?.text ?? "")
        })
        presenter.present(alert, animated: true)
    }

    static func confirmDelete(
        from presenter: UIViewController,
        nodeName: String,
        completion: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: "删除 NBT 节点？", message: nodeName, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { _ in completion() })
        presenter.present(alert, animated: true)
    }

    private static func presentListTypePicker(
        from presenter: UIViewController,
        sourceView: UIView?,
        completion: @escaping (NBTTagType) -> Void
    ) {
        let sheet = UIAlertController(title: "List 元素类型", message: "NBT List 中所有元素必须使用同一种类型", preferredStyle: .actionSheet)
        for type in creatableTypes where type != .list {
            sheet.addAction(UIAlertAction(title: type.displayName, style: .default) { _ in completion(type) })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        configurePopover(sheet, sourceView: sourceView ?? presenter.view)
        presenter.present(sheet, animated: true)
    }

    private static func presentInput(
        from presenter: UIViewController,
        type: NBTTagType,
        listElementType: NBTTagType?,
        requiresName: Bool,
        completion: @escaping (_ name: String?, _ value: NBTValue) -> Void
    ) {
        let needsValue = ![NBTTagType.compound, .list].contains(type)
        let message: String
        switch type {
        case .byteArray, .intArray, .longArray:
            message = "数组数值使用逗号或空格分隔；留空创建空数组。"
        case .compound:
            message = "创建空 Compound。"
        case .list:
            message = "创建空 List<\((listElementType ?? .compound).displayName)>。"
        default:
            message = "输入初始值；数值留空时使用 0。"
        }
        let alert = UIAlertController(title: "增加 \(type.displayName)", message: message, preferredStyle: .alert)
        if requiresName {
            alert.addTextField { field in
                field.placeholder = "标签名称"
                field.autocapitalizationType = .none
                field.autocorrectionType = .no
            }
        }
        if needsValue {
            alert.addTextField { field in
                field.placeholder = type == .string ? "字符串内容" : "初始值"
                field.clearButtonMode = .whileEditing
                if [.byte, .short, .int, .long, .float, .double, .byteArray, .intArray, .longArray].contains(type) {
                    field.keyboardType = .numbersAndPunctuation
                }
            }
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "增加", style: .default) { [weak presenter, weak alert] _ in
            guard let presenter = presenter else { return }
            let fields = alert?.textFields ?? []
            let name: String? = requiresName ? fields.first?.text : nil
            let valueText = needsValue ? fields.last?.text ?? "" : ""
            do {
                let value: NBTValue
                if type == .list {
                    value = .list(listElementType ?? .compound, [])
                } else {
                    value = try NBTTreeMutation.parseInitialValue(valueText, type: type)
                }
                completion(name, value)
            } catch {
                presenter.showError(error, title: "无法增加 NBT 节点")
            }
        })
        presenter.present(alert, animated: true)
    }

    private static func configurePopover(_ controller: UIAlertController, sourceView: UIView) {
        guard let popover = controller.popoverPresentationController else { return }
        popover.sourceView = sourceView
        popover.sourceRect = CGRect(x: sourceView.bounds.midX, y: sourceView.bounds.midY, width: 1, height: 1)
    }
}


extension NBTValue {
    fileprivate var isPasteContainer: Bool {
        switch self {
        case .compound, .list: return true
        default: return false
        }
    }

    fileprivate var scalarClipboardText: String? {
        switch self {
        case .byte(let value): return String(value)
        case .short(let value): return String(value)
        case .int(let value): return String(value)
        case .long(let value): return String(value)
        case .float(let value): return String(value)
        case .double(let value): return String(value)
        case .string(let value): return value
        case .byteArray, .intArray, .longArray, .list, .compound: return nil
        }
    }
}
