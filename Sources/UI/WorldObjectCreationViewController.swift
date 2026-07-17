import UIKit
import MobileCoreServices

final class WorldObjectCreationViewController: UIViewController, UITextFieldDelegate, UIDocumentPickerDelegate {
    private let session: WorldSession
    private let kind: BedrockWorldObjectKind
    private let template: BedrockWorldObject?
    private let onCreate: () -> Void
    private let store: BedrockWorldObjectNBTStore

    private let identifierField = UITextField()
    private let xField = UITextField()
    private let yField = UITextField()
    private let zField = UITextField()
    private let uniqueIDField = UITextField()
    private let dimensionControl = UISegmentedControl(items: BedrockDimension.allCases.map(\.displayName))
    private let uniqueIDRow = UIStackView()
    private let noticeLabel = UILabel()
    private let importNBTButton = UIButton(type: .system)

    init(
        session: WorldSession,
        kind: BedrockWorldObjectKind,
        template: BedrockWorldObject? = nil,
        onCreate: @escaping () -> Void
    ) {
        self.session = session
        self.kind = kind
        self.template = template
        self.onCreate = onCreate
        self.store = BedrockWorldObjectNBTStore(session: session)
        super.init(nibName: nil, bundle: nil)
        title = template == nil ? "新建\(kind.displayName)" : "复制为新\(kind.displayName)"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        configureUI()
        populateDefaults()
    }

    private func configureUI() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "创建",
            style: .done,
            target: self,
            action: #selector(createObject)
        )

        identifierField.placeholder = kind == .entity ? "minecraft:zombie" : "Chest"
        identifierField.autocapitalizationType = .none
        identifierField.autocorrectionType = .no
        identifierField.clearButtonMode = .whileEditing
        identifierField.returnKeyType = .next
        identifierField.delegate = self

        for field in [xField, yField, zField, uniqueIDField] {
            field.keyboardType = .numbersAndPunctuation
            field.clearButtonMode = .whileEditing
            field.textAlignment = .right
            field.font = .monospacedDigitSystemFont(ofSize: 16, weight: .regular)
            field.delegate = self
        }
        xField.placeholder = "X"
        yField.placeholder = "Y"
        zField.placeholder = "Z"
        uniqueIDField.placeholder = "Int64"

        dimensionControl.selectedSegmentIndex = 0

        let form = UIStackView()
        form.axis = .vertical
        form.spacing = 1
        form.backgroundColor = .separator
        form.layer.cornerRadius = 12
        form.clipsToBounds = true
        form.translatesAutoresizingMaskIntoConstraints = false

        form.addArrangedSubview(makeRow(title: kind == .entity ? "实体 ID" : "方块实体 ID", control: identifierField))
        form.addArrangedSubview(makeRow(title: "维度", control: dimensionControl))
        form.addArrangedSubview(makeCoordinateRow())

        uniqueIDRow.axis = .horizontal
        uniqueIDRow.alignment = .center
        uniqueIDRow.spacing = 12
        uniqueIDRow.backgroundColor = .secondarySystemGroupedBackground
        uniqueIDRow.isLayoutMarginsRelativeArrangement = true
        uniqueIDRow.layoutMargins = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        let uniqueLabel = UILabel()
        uniqueLabel.text = "UniqueID"
        uniqueLabel.setContentHuggingPriority(.required, for: .horizontal)
        let regenerate = UIButton(type: .system)
        regenerate.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        regenerate.accessibilityLabel = "重新生成 UniqueID"
        regenerate.addTarget(self, action: #selector(regenerateUniqueID), for: .touchUpInside)
        uniqueIDRow.addArrangedSubview(uniqueLabel)
        uniqueIDRow.addArrangedSubview(uniqueIDField)
        uniqueIDRow.addArrangedSubview(regenerate)
        form.addArrangedSubview(uniqueIDRow)
        uniqueIDRow.isHidden = kind != .entity

        noticeLabel.font = .preferredFont(forTextStyle: .footnote)
        noticeLabel.textColor = .secondaryLabel
        noticeLabel.numberOfLines = 0
        noticeLabel.translatesAutoresizingMaskIntoConstraints = false
        if template == nil {
            noticeLabel.text = kind == .entity
                ? "会自动识别世界的实体存储格式：旧式世界写入区块 Entity(0x32)，现代世界写入 actorprefix/digp。空白模板包含实体通用 NBT 标签；类型专属数据可从现有同类实体复制或从连续 NBT 文件导入。"
                : "方块实体会写入目标区块的 BlockEntity(0x31) 记录。请确保目标坐标的方块类型与方块实体 ID 相匹配。"
        } else {
            noticeLabel.text = "将完整复制“\(template?.displayName ?? kind.displayName)”的 NBT，并根据目标世界及原对象自动选择区块 Entity 或 actorprefix；原对象不会被修改。"
        }

        let selectedButton = UIButton(type: .system)
        selectedButton.setTitle("使用当前选中位置", for: .normal)
        selectedButton.setImage(UIImage(systemName: "scope"), for: .normal)
        selectedButton.addTarget(self, action: #selector(useSelectedPosition), for: .touchUpInside)
        selectedButton.backgroundColor = .secondarySystemGroupedBackground
        selectedButton.layer.cornerRadius = 10
        selectedButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        selectedButton.translatesAutoresizingMaskIntoConstraints = false

        importNBTButton.setTitle("从连续多根 NBT 文件导入…", for: .normal)
        importNBTButton.setImage(UIImage(systemName: "doc.badge.plus"), for: .normal)
        importNBTButton.addTarget(self, action: #selector(selectEntityNBTFile), for: .touchUpInside)
        importNBTButton.backgroundColor = .secondarySystemGroupedBackground
        importNBTButton.layer.cornerRadius = 10
        importNBTButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        importNBTButton.translatesAutoresizingMaskIntoConstraints = false
        importNBTButton.isHidden = kind != .entity || template != nil

        view.addSubview(form)
        view.addSubview(selectedButton)
        view.addSubview(importNBTButton)
        view.addSubview(noticeLabel)
        NSLayoutConstraint.activate([
            form.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            form.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            form.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            selectedButton.leadingAnchor.constraint(equalTo: form.leadingAnchor),
            selectedButton.trailingAnchor.constraint(equalTo: form.trailingAnchor),
            selectedButton.topAnchor.constraint(equalTo: form.bottomAnchor, constant: 14),
            selectedButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            importNBTButton.leadingAnchor.constraint(equalTo: form.leadingAnchor),
            importNBTButton.trailingAnchor.constraint(equalTo: form.trailingAnchor),
            importNBTButton.topAnchor.constraint(equalTo: selectedButton.bottomAnchor, constant: 10),
            importNBTButton.heightAnchor.constraint(equalToConstant: importNBTButton.isHidden ? 0 : 44),
            noticeLabel.leadingAnchor.constraint(equalTo: form.leadingAnchor, constant: 4),
            noticeLabel.trailingAnchor.constraint(equalTo: form.trailingAnchor, constant: -4),
            noticeLabel.topAnchor.constraint(
                equalTo: importNBTButton.isHidden ? selectedButton.bottomAnchor : importNBTButton.bottomAnchor,
                constant: 14
            )
        ])
    }

    private func makeRow(title: String, control: UIView) -> UIStackView {
        let label = UILabel()
        label.text = title
        label.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [label, control])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 14
        row.backgroundColor = .secondarySystemGroupedBackground
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        return row
    }

    private func makeCoordinateRow() -> UIStackView {
        let title = UILabel()
        title.text = "坐标"
        title.setContentHuggingPriority(.required, for: .horizontal)
        let coordinates = UIStackView(arrangedSubviews: [xField, yField, zField])
        coordinates.axis = .horizontal
        coordinates.spacing = 8
        coordinates.distribution = .fillEqually
        let row = UIStackView(arrangedSubviews: [title, coordinates])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 14
        row.backgroundColor = .secondarySystemGroupedBackground
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        return row
    }

    private func populateDefaults() {
        identifierField.text = template?.identifier ?? (kind == .entity ? "minecraft:pig" : "Chest")
        if kind == .entity { regenerateUniqueID() }

        if let position = template?.position {
            setPosition(x: position.x, y: position.y, z: position.z, dimension: template?.dimension ?? 0)
        } else if let selected = session.selectedWorldObjectCoordinate ?? session.selectedBlockCoordinate {
            setPosition(x: selected.x, y: selected.y, z: selected.z, dimension: selected.dimension)
        } else {
            setPosition(x: 0, y: 64, z: 0, dimension: 0)
        }
    }

    private func setPosition(x: Double, y: Double, z: Double, dimension: Int32) {
        xField.text = format(x)
        yField.text = format(y)
        zField.text = format(z)
        if let index = BedrockDimension.allCases.firstIndex(where: { $0.rawValue == dimension }) {
            dimensionControl.selectedSegmentIndex = index
        }
    }

    @objc private func useSelectedPosition() {
        guard let selected = session.selectedWorldObjectCoordinate ?? session.selectedBlockCoordinate else {
            showError(
                BlocktopographError.unsupported("尚未在地图或实体栏目中选中带坐标的对象。"),
                title: "没有选中位置"
            )
            return
        }
        setPosition(x: selected.x, y: selected.y, z: selected.z, dimension: selected.dimension)
        navigationItem.prompt = "已使用选中位置：\(selected.blockDescription)"
    }

    @objc private func regenerateUniqueID() {
        uniqueIDField.text = String(Int64.random(in: 1...Int64.max))
    }

    @objc private func selectEntityNBTFile() {
        view.endEditing(true)
        do {
            _ = try entityImportConfiguration()
        } catch {
            showError(error, title: "导入参数错误")
            return
        }
        let picker = UIDocumentPickerViewController(documentTypes: [kUTTypeItem as String], in: .import)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        guard url.pathExtension.lowercased() == "nbt" else {
            showError(BlocktopographError.unsupported("请选择包含连续多根标签的 .nbt 文件。"), title: "文件格式错误")
            return
        }
        do {
            let configuration = try entityImportConfiguration()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let decoded = try StandaloneNBTFileCodec.decode(data: Data(contentsOf: url), filename: url.lastPathComponent)
            guard decoded.documents.count >= 2 else {
                throw BlocktopographError.unsupported("实体导入文件必须是连续多根 NBT，至少包含两个根标签。")
            }
            var prepared = [NBTDocument]()
            prepared.reserveCapacity(decoded.documents.count)
            for (index, document) in decoded.documents.enumerated() {
                let addition = configuration.uniqueID.addingReportingOverflow(Int64(index))
                guard !addition.overflow, addition.partialValue != 0 else {
                    throw BlocktopographError.malformedData("连续实体 UniqueID 超出 Int64 范围。")
                }
                prepared.append(try store.prepareEntityDocument(
                    document,
                    fallbackIdentifier: configuration.identifier,
                    position: configuration.position,
                    dimension: configuration.dimension,
                    uniqueID: addition.partialValue
                ))
            }
            let returnController = navigationController?.viewControllers.dropLast().last
            let review = EntityNBTImportReviewViewController(
                session: session,
                documents: prepared,
                onComplete: { [weak self] results in
                    guard let self = self else { return }
                    self.onCreate()
                    let message = "已导入 \(results.count) 个实体；对象记录正在重新扫描。"
                    if let destination = returnController {
                        self.navigationController?.popToViewController(destination, animated: true)
                        destination.navigationItem.prompt = message
                    } else {
                        self.navigationController?.popToRootViewController(animated: true)
                    }
                }
            )
            navigationController?.pushViewController(review, animated: true)
        } catch {
            showError(error, title: "读取实体 NBT 失败")
        }
    }

    private func entityImportConfiguration() throws -> (
        identifier: String,
        position: BedrockWorldObjectPosition,
        dimension: Int32,
        uniqueID: Int64
    ) {
        guard kind == .entity, template == nil else {
            throw BlocktopographError.unsupported("只有空白新建实体支持从连续 NBT 文件导入。")
        }
        let identifier = identifierField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !identifier.isEmpty else { throw BlocktopographError.malformedData("请先填写实体 ID。") }
        guard let x = Double(xField.text ?? ""),
              let y = Double(yField.text ?? ""),
              let z = Double(zField.text ?? ""),
              x.isFinite, y.isFinite, z.isFinite else {
            throw BlocktopographError.malformedData("请先填写有效的实体 X、Y、Z 坐标。")
        }
        guard let uniqueID = Int64(uniqueIDField.text ?? ""), uniqueID != 0 else {
            throw BlocktopographError.malformedData("请先填写非零 Int64 UniqueID。")
        }
        let index = max(0, dimensionControl.selectedSegmentIndex)
        return (
            identifier,
            BedrockWorldObjectPosition(x: x, y: y, z: z),
            BedrockDimension.allCases[index].rawValue,
            uniqueID
        )
    }

    @objc private func createObject() {
        view.endEditing(true)
        guard let x = Double(xField.text ?? ""),
              let y = Double(yField.text ?? ""),
              let z = Double(zField.text ?? "") else {
            showError(BlocktopographError.malformedData("X、Y、Z 必须是有效数字。"), title: "坐标错误")
            return
        }
        let identifier = identifierField.text ?? ""
        let dimensionIndex = max(0, dimensionControl.selectedSegmentIndex)
        let dimension = BedrockDimension.allCases[dimensionIndex].rawValue
        let uniqueID: Int64?
        if kind == .entity {
            guard let parsed = Int64(uniqueIDField.text ?? "") else {
                showError(BlocktopographError.malformedData("UniqueID 必须是 Int64 整数。"), title: "UniqueID 错误")
                return
            }
            uniqueID = parsed
        } else {
            uniqueID = nil
        }

        do {
            let result = try store.create(
                kind: kind,
                identifier: identifier,
                position: BedrockWorldObjectPosition(x: x, y: y, z: z),
                dimension: dimension,
                uniqueID: uniqueID,
                template: template
            )
            session.invalidateAfterExternalChange()
            onCreate()
            let idText = result.uniqueID.map { "；UniqueID \($0)" } ?? ""
            let storageText = kind == .entity ? "；存储：\(result.source.rawValue)" : ""
            navigationController?.popViewController(animated: true)
            navigationController?.topViewController?.navigationItem.prompt = "已创建\(kind.displayName)：区块 (\(result.chunkX), \(result.chunkZ))\(idText)\(storageText)"
        } catch {
            showError(error, title: "创建\(kind.displayName)失败")
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === identifierField {
            xField.becomeFirstResponder()
        } else if textField === xField {
            yField.becomeFirstResponder()
        } else if textField === yField {
            zField.becomeFirstResponder()
        } else if textField === zField && kind == .entity {
            uniqueIDField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
        }
        return true
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int64(value)) : String(format: "%.3f", value)
    }
}
