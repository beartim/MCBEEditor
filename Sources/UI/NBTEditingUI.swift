import UIKit
import MobileCoreServices

enum NBTEditingUI {

    typealias TagInsertionCompletion = (_ name: String?, _ value: NBTValue, _ replacingExisting: Bool) -> Void

    private static let tagPasteboardType = "com.wzn.mcbeeditor.nbt-tag"
    private static let batchTagPasteboardType = "com.wzn.mcbeeditor.nbt-tags-v1"
    private static let legacyTagPasteboardType = "com.wzn.blocktopograph.nbt-tag"
    private static let legacyBatchTagPasteboardType = "com.wzn.blocktopograph.nbt-tags-v1"
    private static var importPickerCoordinators = [ObjectIdentifier: NBTTagImportPickerCoordinator]()

    static var hasCopiedTag: Bool {
        UIPasteboard.general.data(forPasteboardType: batchTagPasteboardType) != nil ||
        UIPasteboard.general.data(forPasteboardType: tagPasteboardType) != nil ||
        UIPasteboard.general.data(forPasteboardType: legacyBatchTagPasteboardType) != nil ||
        UIPasteboard.general.data(forPasteboardType: legacyTagPasteboardType) != nil
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
            let batch = try NBTClipboardCodec.encodeBatch(documents)
            // Write both custom representations into the same pasteboard item. Calling
            // setData twice can replace the first custom type on iOS, which made a
            // multi-tag copy fall back to the legacy single-tag payload.
            UIPasteboard.general.setItems([[
                batchTagPasteboardType: batch,
                tagPasteboardType: encoded[0]
            ]])
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
        guard container.isPasteContainer else {
            presenter.showError(MCBEEditorError.unsupported("只能向 Compound 或 List 增加节点"), title: "无法增加")
            return
        }
        let sheet = UIAlertController(title: "增加 NBT 标签", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "新建标签", style: .default) { _ in
            presentNewTag(from: presenter, container: container, sourceView: sourceView, completion: completion)
        })
        sheet.addAction(UIAlertAction(title: "导入 NBT／mcstructure／JSON…", style: .default) { _ in
            presentImport(from: presenter, container: container, sourceView: sourceView, completion: completion)
        })
        if hasCopiedTag {
            sheet.addAction(UIAlertAction(title: "粘贴已复制标签", style: .default) { _ in
                presentPaste(from: presenter, container: container, sourceView: sourceView, completion: completion)
            })
        }
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
                throw MCBEEditorError.malformedData("剪贴板中没有 MCBEEditor NBT 标签")
            }
            presentInsertion(
                from: presenter,
                container: container,
                items: copied,
                emptyNameBase: "复制的标签",
                operation: "粘贴",
                completion: completion
            )
        } catch {
            presenter.showError(error, title: "粘贴标签失败")
        }
    }

    static func presentImport(
        from presenter: UIViewController,
        container: NBTValue,
        sourceView: UIView? = nil,
        completion: @escaping TagInsertionCompletion
    ) {
        presentImportPicker(from: presenter) { documents, baseName in
            let items = documents.enumerated().map { index, document -> (name: String, value: NBTValue) in
                let trimmed = document.rootName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return (trimmed, document.root) }
                let fallback = documents.count == 1 ? baseName : "\(baseName) \(index + 1)"
                return (fallback, document.root)
            }
            presentInsertion(
                from: presenter,
                container: container,
                items: items,
                emptyNameBase: baseName,
                operation: "导入",
                completion: completion
            )
        }
    }

    private static func presentInsertion(
        from presenter: UIViewController,
        container: NBTValue,
        items: [(name: String, value: NBTValue)],
        emptyNameBase: String,
        operation: String,
        completion: @escaping TagInsertionCompletion
    ) {
        guard !items.isEmpty else {
            presenter.showError(MCBEEditorError.malformedData("没有可\(operation)的 NBT 标签"), title: "\(operation)标签失败")
            return
        }
        do {
            switch container {
            case .compound(let existing):
                let existingNames = Set(existing.map(\.name))
                let prepared = preparedCompoundTags(
                    items,
                    existingNames: existingNames,
                    emptyNameBase: emptyNameBase
                )
                var observedNames = existingNames
                var conflictNames = Set<String>()
                for item in prepared {
                    if observedNames.contains(item.name) { conflictNames.insert(item.name) }
                    observedNames.insert(item.name)
                }

                let apply: (_ overwrite: Bool) -> Void = { overwrite in
                    var occupiedNames = existingNames
                    var insertedCount = 0
                    for item in prepared {
                        let conflicts = occupiedNames.contains(item.name)
                        if conflicts, !overwrite { continue }
                        completion(item.name, item.value, overwrite && conflicts)
                        occupiedNames.insert(item.name)
                        insertedCount += 1
                    }
                    if conflictNames.isEmpty {
                        presenter.navigationItem.prompt = insertedCount == 1
                            ? "已\(operation) NBT 标签"
                            : "已\(operation) \(insertedCount) 个 NBT 标签"
                    } else if overwrite {
                        presenter.navigationItem.prompt = "已\(operation) \(insertedCount) 个标签并覆盖同名标签"
                    } else {
                        presenter.navigationItem.prompt = "已\(operation) \(insertedCount) 个标签；同名标签已保留"
                    }
                }

                guard !conflictNames.isEmpty else {
                    apply(false)
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
                alert.addAction(UIAlertAction(title: "保留", style: .default) { _ in apply(false) })
                alert.addAction(UIAlertAction(title: "覆盖", style: .destructive) { _ in apply(true) })
                presenter.present(alert, animated: true)

            case .list(let elementType, let values):
                let expectedType: NBTTagType
                if elementType == .end, values.isEmpty {
                    expectedType = items[0].value.type
                } else {
                    expectedType = elementType
                }
                guard items.allSatisfy({ $0.value.type == expectedType }) else {
                    let importedTypes = Set(items.map { $0.value.type.displayName }).sorted().joined(separator: "、")
                    throw MCBEEditorError.malformedData(
                        "该 List 只能\(operation) \(expectedType.displayName)，所选标签包含：\(importedTypes)"
                    )
                }
                for item in items { completion(nil, item.value, false) }
                presenter.navigationItem.prompt = items.count == 1
                    ? "已\(operation) NBT 标签"
                    : "已\(operation) \(items.count) 个 NBT 标签"
            default:
                throw MCBEEditorError.unsupported("只能向 Compound 或 List \(operation)标签")
            }
        } catch {
            presenter.showError(error, title: "\(operation)标签失败")
        }
    }

    private static func preparedCompoundTags(
        _ items: [(name: String, value: NBTValue)],
        existingNames: Set<String>,
        emptyNameBase: String
    ) -> [(name: String, value: NBTValue)] {
        var generatedNames = existingNames
        let cleanedBase = emptyNameBase.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleanedBase.isEmpty ? "导入的标签" : cleanedBase
        return items.map { item in
            let trimmed = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty else { return (trimmed, item.value) }
            let name = uniqueName(base: base, usedNames: &generatedNames)
            return (name, item.value)
        }
    }

    private static func copiedTags() throws -> [(name: String, value: NBTValue)] {
        if let batch = UIPasteboard.general.data(forPasteboardType: batchTagPasteboardType)
            ?? UIPasteboard.general.data(forPasteboardType: legacyBatchTagPasteboardType),
           NBTClipboardCodec.isBatchPayload(batch) {
            return try NBTClipboardCodec.decodeBatch(batch).map { ($0.rootName, $0.root) }
        }
        guard let data = UIPasteboard.general.data(forPasteboardType: tagPasteboardType)
            ?? UIPasteboard.general.data(forPasteboardType: legacyTagPasteboardType) else {
            throw MCBEEditorError.malformedData("剪贴板中没有 MCBEEditor NBT 标签")
        }
        let document = try BedrockNBTCodec.decode(data, encoding: .littleEndian)
        return [(document.rootName, document.root)]
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
        completion: @escaping ([NBTDocument]) -> Void
    ) {
        let sheet = UIAlertController(
            title: "新建 NBT 根标签",
            message: "选择根标签类型，或从 nbt／mcstructure／json 文件导入。",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "导入 NBT／mcstructure／JSON…", style: .default) { _ in
            presentImportPicker(from: presenter) { documents, _ in
                completion(documents)
                presenter.navigationItem.prompt = documents.count == 1
                    ? "已导入 NBT 根标签"
                    : "已导入 \(documents.count) 个 NBT 根标签"
            }
        })
        for type in creatableTypes {
            sheet.addAction(UIAlertAction(title: type.displayName, style: .default) { _ in
                let finish: (String?, NBTValue) -> Void = { name, value in
                    completion([NBTDocument(rootName: name ?? "", root: value)])
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
        completion: @escaping TagInsertionCompletion
    ) {
        guard container.isPasteContainer else {
            presenter.showError(MCBEEditorError.unsupported("只能向 Compound 或 List 增加节点"), title: "无法增加")
            return
        }
        let sheet = UIAlertController(title: "增加 NBT 标签", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "新建标签", style: .default) { _ in
            presentNewTag(from: presenter, container: container, sourceView: sourceView, completion: completion)
        })
        sheet.addAction(UIAlertAction(title: "导入 NBT／mcstructure／JSON…", style: .default) { _ in
            presentImport(from: presenter, container: container, sourceView: sourceView, completion: completion)
        })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        configurePopover(sheet, sourceView: sourceView ?? presenter.view)
        presenter.present(sheet, animated: true)
    }

    private static func presentNewTag(
        from presenter: UIViewController,
        container: NBTValue,
        sourceView: UIView?,
        completion: @escaping TagInsertionCompletion
    ) {
        let finish: (String?, NBTValue) -> Void = { name, value in
            completion(name, value, false)
        }
        switch container {
        case .compound:
            let sheet = UIAlertController(title: "新建 NBT 标签", message: "选择新标签类型", preferredStyle: .actionSheet)
            for type in creatableTypes {
                sheet.addAction(UIAlertAction(title: type.displayName, style: .default) { _ in
                    if type == .list {
                        presentListTypePicker(from: presenter, sourceView: sourceView) { listType in
                            presentInput(from: presenter, type: type, listElementType: listType, requiresName: true, completion: finish)
                        }
                    } else {
                        presentInput(from: presenter, type: type, listElementType: nil, requiresName: true, completion: finish)
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
                                presentInput(from: presenter, type: .list, listElementType: nestedType, requiresName: false, completion: finish)
                            }
                        } else {
                            presentInput(from: presenter, type: type, listElementType: nil, requiresName: false, completion: finish)
                        }
                    })
                }
                sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
                configurePopover(sheet, sourceView: sourceView ?? presenter.view)
                presenter.present(sheet, animated: true)
            } else {
                presentInput(from: presenter, type: elementType, listElementType: nil, requiresName: false, completion: finish)
            }
        default:
            presenter.showError(MCBEEditorError.unsupported("只能向 Compound 或 List 增加节点"), title: "无法增加")
        }
    }

    static func presentEdit(
        from presenter: UIViewController,
        node: NBTNode,
        completion: @escaping (NBTValue) -> Void
    ) {
        guard let initialText = node.value.editableText else {
            presenter.showError(
                MCBEEditorError.unsupported("Compound 和 List 请通过增加、删除或编辑子节点修改。"),
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

    private static func presentImportPicker(
        from presenter: UIViewController,
        completion: @escaping (_ documents: [NBTDocument], _ baseName: String) -> Void
    ) {
        let picker = UIDocumentPickerViewController(
            documentTypes: [kUTTypeItem as String],
            in: .import
        )
        picker.allowsMultipleSelection = false
        let identifier = ObjectIdentifier(picker)
        let coordinator = NBTTagImportPickerCoordinator(
            presenter: presenter,
            completion: completion
        ) {
            importPickerCoordinators.removeValue(forKey: identifier)
        }
        importPickerCoordinators[identifier] = coordinator
        picker.delegate = coordinator
        presenter.present(picker, animated: true)
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

private final class NBTTagImportPickerCoordinator: NSObject, UIDocumentPickerDelegate {
    private weak var presenter: UIViewController?
    private let completion: ([NBTDocument], String) -> Void
    private let finish: () -> Void

    init(
        presenter: UIViewController,
        completion: @escaping ([NBTDocument], String) -> Void,
        finish: @escaping () -> Void
    ) {
        self.presenter = presenter
        self.completion = completion
        self.finish = finish
        super.init()
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        defer { finish() }
        guard let presenter = presenter, let url = urls.first else { return }
        let ext = url.pathExtension.lowercased()
        guard ext == "nbt" || ext == "mcstructure" || ext == "json" else {
            presenter.showError(
                MCBEEditorError.unsupported("请选择 .nbt、.mcstructure 或 .json 文件"),
                title: "无法导入 NBT 标签"
            )
            return
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try StandaloneNBTFileCodec.decode(data: data, filename: url.lastPathComponent)
            guard !decoded.documents.isEmpty else {
                throw MCBEEditorError.malformedData("文件中没有 NBT 根标签")
            }
            let baseName = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            completion(decoded.documents, baseName.isEmpty ? "导入的标签" : baseName)
        } catch {
            presenter.showError(error, title: "导入 NBT 标签失败")
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish()
    }
}
