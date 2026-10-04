import UIKit

enum NBTExportUI {
    static func presentFormatChooser(
        from presenter: UIViewController,
        documents: [NBTDocument],
        baseFilename: String,
        allowMCStructure: Bool = false,
        originalFile: (filename: String, data: Data)? = nil,
        barButtonItem: UIBarButtonItem? = nil,
        sourceView: UIView? = nil
    ) {
        guard !documents.isEmpty else {
            presenter.showError(MCBEEditorError.unsupported("没有可导出的 NBT 标签"), title: "无法导出")
            return
        }
        let sheet = UIAlertController(
            title: documents.count == 1 ? "导出 NBT" : "导出 \(documents.count) 个 NBT 标签",
            message: "请选择导出格式。多个根标签保持原顺序；MCBE-SNBT 为带类型的 .txt 文本。",
            preferredStyle: .actionSheet
        )
        if let originalFile = originalFile {
            sheet.addAction(UIAlertAction(title: "原始 NBT 数据", style: .default) { _ in
                export(from: presenter, filename: safeFilename(originalFile.filename)) { originalFile.data }
            })
        }
        sheet.addAction(UIAlertAction(title: "MCBE-SNBT (.txt)", style: .default) { _ in
            export(from: presenter, filename: safeFilename(baseFilename) + ".txt") {
                try StandaloneNBTFileCodec.encodeMCBESNBT(documents)
            }
        })
        sheet.addAction(UIAlertAction(title: "JSON NBT (.json)", style: .default) { _ in
            export(from: presenter, filename: safeFilename(baseFilename) + ".json") {
                try NBTJSONCodec.encode(documents)
            }
        })
        sheet.addAction(UIAlertAction(title: "Little Endian NBT", style: .default) { _ in
            export(from: presenter, filename: safeFilename(baseFilename) + "-little-endian.nbt") {
                try StandaloneNBTFileCodec.encode(documents, encoding: .littleEndian)
            }
        })
        sheet.addAction(UIAlertAction(title: "Little Endian VarInt NBT", style: .default) { _ in
            export(from: presenter, filename: safeFilename(baseFilename) + "-little-varint.nbt") {
                try StandaloneNBTFileCodec.encode(documents, encoding: .littleEndianVarInt)
            }
        })
        sheet.addAction(UIAlertAction(title: "Big Endian NBT", style: .default) { _ in
            export(from: presenter, filename: safeFilename(baseFilename) + "-big-endian.nbt") {
                try StandaloneNBTFileCodec.encode(documents, encoding: .bigEndian)
            }
        })
        if allowMCStructure, documents.count == 1 {
            sheet.addAction(UIAlertAction(title: "Bedrock mcstructure", style: .default) { _ in
                export(from: presenter, filename: safeFilename(baseFilename) + ".mcstructure") {
                    try StandaloneNBTFileCodec.encodeAsMCStructure(documents).data
                }
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            if let barButtonItem = barButtonItem {
                popover.barButtonItem = barButtonItem
            } else {
                presenter.loadViewIfNeeded()
                if let anchor = sourceView ?? presenter.viewIfLoaded {
                    popover.sourceView = anchor
                    popover.sourceRect = CGRect(
                        x: anchor.bounds.midX,
                        y: anchor.bounds.midY,
                        width: 1,
                        height: 1
                    )
                }
            }
        }
        presenter.present(sheet, animated: true)
    }

    static func presentEntityFormatChooser(
        from presenter: UIViewController,
        document: NBTDocument,
        baseFilename: String,
        sourceView: UIView? = nil
    ) {
        let sheet = UIAlertController(
            title: "导出实体 NBT",
            message: "仅导出当前选中实体的全部标签。请选择格式。",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "MCBE-SNBT (.txt)", style: .default) { _ in
            export(from: presenter, filename: safeFilename(baseFilename) + ".txt") {
                try StandaloneNBTFileCodec.encodeMCBESNBT([document])
            }
        })
        sheet.addAction(UIAlertAction(title: "实体 JSON (.json)", style: .default) { _ in
            export(from: presenter, filename: safeFilename(baseFilename) + ".json") {
                try NBTJSONCodec.encodeEntityDocument(document)
            }
        })
        sheet.addAction(UIAlertAction(title: "Little Endian NBT", style: .default) { _ in
            export(from: presenter, filename: safeFilename(baseFilename) + "-little-endian.nbt") {
                try StandaloneNBTFileCodec.encode([document], encoding: .littleEndian)
            }
        })
        sheet.addAction(UIAlertAction(title: "Little Endian VarInt NBT", style: .default) { _ in
            export(from: presenter, filename: safeFilename(baseFilename) + "-little-varint.nbt") {
                try StandaloneNBTFileCodec.encode([document], encoding: .littleEndianVarInt)
            }
        })
        sheet.addAction(UIAlertAction(title: "Big Endian NBT", style: .default) { _ in
            export(from: presenter, filename: safeFilename(baseFilename) + "-big-endian.nbt") {
                try StandaloneNBTFileCodec.encode([document], encoding: .bigEndian)
            }
        })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            presenter.loadViewIfNeeded()
            let anchor = sourceView ?? presenter.viewIfLoaded
            popover.sourceView = anchor
            popover.sourceRect = CGRect(x: anchor?.bounds.midX ?? 0, y: anchor?.bounds.midY ?? 0, width: 1, height: 1)
        }
        presenter.present(sheet, animated: true)
    }

    static func exportConsecutiveLittleEndian(
        from presenter: UIViewController,
        documents: [NBTDocument],
        baseFilename: String
    ) {
        presentFormatChooser(from: presenter, documents: documents, baseFilename: baseFilename + "-consecutive")
    }

    static func documents(from nodes: [NBTNode]) -> [NBTDocument] {
        nodes.map { node in
            let rawName: String
            if case .compound(let name)? = node.path.last { rawName = name }
            else if case .list? = node.path.last { rawName = "item" }
            else { rawName = node.name }
            return NBTDocument(rootName: rawName, root: node.value)
        }
    }

    private static func export(
        from presenter: UIViewController,
        filename: String,
        producer: @escaping () throws -> Data
    ) {
        let overlay = presenter.showBusy("生成导出文件…")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try producer()
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try data.write(to: url, options: .atomic)
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    activity.popoverPresentationController?.sourceView = presenter.view
                    activity.popoverPresentationController?.sourceRect = CGRect(
                        x: presenter.view.bounds.midX,
                        y: presenter.view.bounds.midY,
                        width: 1,
                        height: 1
                    )
                    presenter.present(activity, animated: true)
                }
            } catch {
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    presenter.showError(error, title: "导出失败")
                }
            }
        }
    }

    private static func safeFilename(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = value.components(separatedBy: forbidden).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "nbt-export" : String(cleaned.prefix(120))
    }
}
