import UIKit

enum NBTExportUI {
    static func presentFormatChooser(
        from presenter: UIViewController,
        documents: [NBTDocument],
        baseFilename: String,
        allowMCStructure: Bool = false,
        barButtonItem: UIBarButtonItem? = nil,
        sourceView: UIView? = nil
    ) {
        guard !documents.isEmpty else {
            presenter.showError(BlocktopographError.unsupported("没有可导出的 NBT 标签"), title: "无法导出")
            return
        }
        let sheet = UIAlertController(
            title: documents.count == 1 ? "导出 NBT" : "导出 \(documents.count) 个 NBT 标签",
            message: "请选择导出格式。多个标签会写成连续 NBT，JSON 会写入 documents 数组。",
            preferredStyle: .actionSheet
        )
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

    static func documents(from nodes: [NBTNode]) -> [NBTDocument] {
        nodes.map { node in
            let rawName = node.name.hasPrefix("[") ? "item" : node.name
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
