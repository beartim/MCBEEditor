import UIKit
import MobileCoreServices

/// Shared file dialogs for the structure list, editor and interactive commands.
/// Completion runs on the main thread, including picker cancellation.
final class StructureFileCoordinator: NSObject, UIDocumentPickerDelegate {
    typealias Completion = (Result<WorldCommandExecutionResult, Error>) -> Void
    private weak var presenter: UIViewController?
    private let store: StructureNBTStore
    private let queue = DispatchQueue(label: "com.wzn.mcbeeditor.structure-files", qos: .userInitiated)
    private var completion: Completion?
    private var importName: String?
    private var exportName: String?
    private var temporaryDirectory: URL?
    private var busyView: UIView?

    private func beginBusy(_ message: String) {
        endBusy()
        busyView = presenter?.showBusy(message)
    }
    private func endBusy() { busyView?.removeFromSuperview(); busyView = nil }

    init(presenter: UIViewController, session: WorldSession) {
        self.presenter = presenter
        store = StructureNBTStore(session: session)
    }

    func importFile(named name: String?, completion: @escaping Completion) {
        self.completion = completion
        importName = name
        exportName = nil
        let picker = UIDocumentPickerViewController(documentTypes: [kUTTypeItem as String], in: .import)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        presenter?.present(picker, animated: true)
    }

    func exportFile(format: StructureFileFormat, named name: String?, completion: @escaping Completion) {
        self.completion = completion
        beginBusy("读取结构列表…")
        queue.async {
            do {
                let records = try self.store.records()
                DispatchQueue.main.async {
                    self.endBusy()
                    if let name = name {
                        guard let record = records.first(where: { self.store.isSameStructure($0, named: name) }) else {
                            self.finish(.failure(MCBEEditorError.unsupported("不存在结构：\(name)")))
                            return
                        }
                        self.export(record: record, format: format)
                    } else if records.isEmpty {
                        self.finish(.success(WorldCommandExecutionResult(message: "没有已保存的结构。", changedWorld: false)))
                    } else {
                        let sheet = UIAlertController(title: "选择要导出的结构", message: nil, preferredStyle: .actionSheet)
                        for record in records {
                            sheet.addAction(UIAlertAction(title: record.displayName, style: .default) { _ in
                                self.export(record: record, format: format)
                            })
                        }
                        sheet.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in self.cancel() })
                        self.presentSheet(sheet)
                    }
                }
            } catch { DispatchQueue.main.async { self.finish(.failure(error)) } }
        }
    }

    func chooseExportFormat(document: NBTDocument, name: String, completion: @escaping Completion) {
        self.completion = completion
        let sheet = UIAlertController(title: "导出结构", message: "请选择文件格式。", preferredStyle: .actionSheet)
        for format in StructureFileFormat.allCases {
            let title = format == .nbt ? "NBT · Big Endian (.nbt)" : ".\(format.rawValue)"
            sheet.addAction(UIAlertAction(title: title, style: .default) { _ in
                self.writeExport(document: document, name: name, format: format)
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in self.cancel() })
        presentSheet(sheet)
    }

    private func presentSheet(_ sheet: UIAlertController) {
        guard let presenter = presenter else { cancel(); return }
        presenter.loadViewIfNeeded()
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
        }
        presenter.present(sheet, animated: true)
    }

    private func export(record: StructureNBTRecord, format: StructureFileFormat) {
        guard let document = record.document else {
            finish(.failure(MCBEEditorError.malformedData("结构 NBT 无法解析：\(record.displayName)")))
            return
        }
        writeExport(document: document, name: record.displayName, format: format)
    }

    private func writeExport(document: NBTDocument, name: String, format: StructureFileFormat) {
        beginBusy("生成结构文件…")
        queue.async {
            do {
                let data = try StandaloneNBTFileCodec.encodeStructure(document, format: format)
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                self.temporaryDirectory = directory
                let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\?%*|\"<>:"))
                let clean = name.components(separatedBy: forbidden).joined(separator: "_")
                let filename = (clean.isEmpty ? "structure" : String(clean.prefix(120))) + "." + format.rawValue
                let url = directory.appendingPathComponent(filename)
                try data.write(to: url, options: .atomic)
                DispatchQueue.main.async {
                    self.endBusy()
                    self.exportName = filename
                    let picker = UIDocumentPickerViewController(url: url, in: .exportToService)
                    picker.delegate = self
                    self.presenter?.present(picker, animated: true)
                }
            } catch { DispatchQueue.main.async { self.finish(.failure(error)) } }
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        controller.dismiss(animated: true) { self.cancel() }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        controller.dismiss(animated: true) {
            if let name = self.exportName {
                self.finish(.success(WorldCommandExecutionResult(message: "structure export 完成：\(name)", changedWorld: false)))
                return
            }
            guard let url = urls.first else { self.cancel(); return }
            self.beginBusy("读取结构文件…")
            self.queue.async {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    guard ["nbt", "mcstructure", "json"].contains(url.pathExtension.lowercased()) else {
                        throw MCBEEditorError.unsupported("请选择 .nbt、.mcstructure 或 .json 文件")
                    }
                    let file = try StandaloneNBTFileCodec.decode(data: Data(contentsOf: url), filename: url.lastPathComponent)
                    guard file.documents.count == 1, let document = file.documents.first else {
                        throw MCBEEditorError.unsupported("结构文件必须只包含一个 NBT 根标签")
                    }
                    DispatchQueue.main.async {
                        self.endBusy()
                        if let name = self.importName { self.checkImport(document: document, name: name) }
                        else { self.promptName(document: document, suggested: url.deletingPathExtension().lastPathComponent) }
                    }
                } catch { DispatchQueue.main.async { self.finish(.failure(error)) } }
            }
        }
    }

    private func promptName(document: NBTDocument, suggested: String) {
        let alert = UIAlertController(title: "指定结构名称", message: "可使用 namespace:name 格式。", preferredStyle: .alert)
        alert.addTextField { field in
            field.text = suggested
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in self.cancel() })
        alert.addAction(UIAlertAction(title: "导入", style: .default) { [weak alert] _ in
            self.checkImport(document: document, name: alert?.textFields?.first?.text ?? "")
        })
        presenter?.present(alert, animated: true)
    }

    private func checkImport(document: NBTDocument, name: String) {
        beginBusy("检查结构名称…")
        queue.async {
            do {
                let name = self.store.normalizedStructureName(name)
                let exists = try self.store.containsStructure(named: name)
                DispatchQueue.main.async {
                    self.endBusy()
                    let write = { self.performImport(document: document, name: name, overwrite: exists) }
                    if exists {
                        let alert = UIAlertController(title: "替换同名结构？", message: "世界中已存在“\(name)”。继续将覆盖原结构。", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in self.cancel() })
                        alert.addAction(UIAlertAction(title: "替换", style: .destructive) { _ in write() })
                        self.presenter?.present(alert, animated: true)
                    } else { write() }
                }
            } catch { DispatchQueue.main.async { self.finish(.failure(error)) } }
        }
    }

    private func performImport(document: NBTDocument, name: String, overwrite: Bool) {
        beginBusy("导入结构…")
        queue.async {
            do {
                let result = try self.store.save(document: document, named: name, overwrite: overwrite)
                var message = "structure import 完成：\(name)"
                if result.convertedFromJava {
                    message += "；Java → Bedrock，\(result.placedBlockCount) 个方块，\(result.lossyPaletteEntryCount) 个调色板条目发生兼容降级；不带入实体、水层及高级方块实体数据。"
                }
                DispatchQueue.main.async { self.finish(.success(WorldCommandExecutionResult(message: message, changedWorld: true))) }
            } catch { DispatchQueue.main.async { self.finish(.failure(error)) } }
        }
    }

    private func cancel() {
        finish(.success(WorldCommandExecutionResult(message: "已取消。", changedWorld: false)))
    }

    private func finish(_ result: Result<WorldCommandExecutionResult, Error>) {
        endBusy()
        let callback = completion
        completion = nil
        if let directory = temporaryDirectory { try? FileManager.default.removeItem(at: directory) }
        temporaryDirectory = nil
        exportName = nil
        callback?(result)
    }
}
