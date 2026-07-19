import UIKit

final class ExperienceEditorViewController: UITableViewController {
    private let session: WorldSession
    private let store: ExperienceStore
    private let workQueue = DispatchQueue(label: "com.wzn.mcbeeditor.experience.list", qos: .userInitiated)
    private var records = [PlayerExperienceRecord]()
    private var isLoading = false

    init(session: WorldSession) {
        self.session = session
        self.store = ExperienceStore(session: session)
        super.init(style: .insetGrouped)
        title = "经验"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(reloadPlayers))
        reloadPlayers()
    }

    @objc private func reloadPlayers() {
        guard !isLoading else { return }
        isLoading = true
        let overlay = showBusy("读取玩家经验…")
        workQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let values = try self.store.records()
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.isLoading = false
                    self.records = values
                    self.tableView.reloadData()
                }
            } catch {
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.isLoading = false
                    self.showError(error, title: "读取经验失败")
                }
            }
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { records.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { "玩家" }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "基岩版实际保存 PlayerLevel 与 PlayerLevelProgress；经验总数由等级曲线和当前经验条进度自动计算。"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ExperiencePlayerCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "ExperiencePlayerCell")
        let item = records[indexPath.row]
        cell.textLabel?.text = item.player.displayName
        let uid = item.uniqueID.map(String.init) ?? "无UniqueID"
        cell.detailTextLabel?.text = String(
            format: "UniqueID %@ · 总数 %lld · 等级 %d · 进度 %.3f",
            uid,
            item.experience.total,
            item.experience.level,
            Double(item.experience.progress)
        )
        cell.detailTextLabel?.numberOfLines = 2
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = records[indexPath.row]
        let controller = PlayerExperienceEditorViewController(session: session, record: item) { [weak self] in
            self?.reloadPlayers()
        }
        navigationController?.pushViewController(controller, animated: true)
    }
}

private final class PlayerExperienceEditorViewController: UIViewController, UITextFieldDelegate {
    private enum EditSource {
        case total
        case levelAndProgress
    }

    private let session: WorldSession
    private let store: ExperienceStore
    private let record: PlayerExperienceRecord
    private let completion: () -> Void
    private let workQueue = DispatchQueue(label: "com.wzn.mcbeeditor.experience.edit", qos: .userInitiated)

    private let stack = UIStackView()
    private let totalField = UITextField()
    private let levelField = UITextField()
    private let progressSlider = UISlider()
    private let progressLabel = UILabel()
    private var editSource = EditSource.levelAndProgress
    private var isSynchronizing = false

    init(session: WorldSession, record: PlayerExperienceRecord, completion: @escaping () -> Void) {
        self.session = session
        self.store = ExperienceStore(session: session)
        self.record = record
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
        title = record.player.displayName
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save))
        configureUI()
        apply(record.experience)
    }

    private func configureUI() {
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 20, left: 18, bottom: 24, right: 18)
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        ])

        let uid = record.uniqueID.map(String.init) ?? "无UniqueID"
        let identity = UILabel()
        identity.font = .preferredFont(forTextStyle: .headline)
        identity.numberOfLines = 0
        identity.text = "minecraft:player · UniqueID \(uid)"
        stack.addArrangedSubview(identity)

        for field in [totalField, levelField] {
            field.borderStyle = .roundedRect
            field.keyboardType = .numbersAndPunctuation
            field.delegate = self
            field.textAlignment = .right
        }
        totalField.addTarget(self, action: #selector(totalChanged), for: .editingChanged)
        levelField.addTarget(self, action: #selector(levelChanged), for: .editingChanged)
        stack.addArrangedSubview(fieldRow(title: "经验总数", field: totalField))
        stack.addArrangedSubview(fieldRow(title: "经验等级", field: levelField))

        progressSlider.minimumValue = 0
        progressSlider.maximumValue = 1
        progressSlider.addTarget(self, action: #selector(progressChanged), for: .valueChanged)
        progressLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        progressLabel.textAlignment = .right
        progressLabel.widthAnchor.constraint(equalToConstant: 70).isActive = true
        let progressRow = UIStackView(arrangedSubviews: [progressSlider, progressLabel])
        progressRow.axis = .horizontal
        progressRow.spacing = 10
        progressRow.alignment = .center
        stack.addArrangedSubview(sectionTitle("当前经验条进度"))
        stack.addArrangedSubview(progressRow)

        let note = UILabel()
        note.font = .preferredFont(forTextStyle: .footnote)
        note.textColor = .secondaryLabel
        note.numberOfLines = 0
        note.text = "修改经验总数会自动换算等级和经验条；修改等级或经验条也会同步更新经验总数。保存时只写入游戏实际使用的 PlayerLevel 与 PlayerLevelProgress。等级范围为 0～24791，经验条进度范围为 0～1，经验总数范围为 0～\(BedrockPlayerExperience.maximumTotal)。"
        stack.addArrangedSubview(note)
    }

    private func sectionTitle(_ title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .headline)
        return label
    }

    private func fieldRow(title: String, field: UITextField) -> UIStackView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [label, field])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        return row
    }

    private func apply(_ experience: BedrockPlayerExperience) {
        isSynchronizing = true
        totalField.text = String(experience.total)
        levelField.text = String(experience.level)
        progressSlider.value = experience.progress
        progressLabel.text = String(format: "%.3f", experience.progress)
        isSynchronizing = false
    }

    @objc private func totalChanged() {
        guard !isSynchronizing else { return }
        editSource = .total
        guard let total = Int64(totalField.text ?? ""),
              let experience = try? BedrockPlayerExperience.fromTotal(total) else { return }
        isSynchronizing = true
        levelField.text = String(experience.level)
        progressSlider.value = experience.progress
        progressLabel.text = String(format: "%.3f", experience.progress)
        isSynchronizing = false
    }

    @objc private func levelChanged() {
        guard !isSynchronizing else { return }
        editSource = .levelAndProgress
        synchronizeTotalFromLevelAndProgress()
    }

    @objc private func progressChanged() {
        progressLabel.text = String(format: "%.3f", progressSlider.value)
        guard !isSynchronizing else { return }
        editSource = .levelAndProgress
        synchronizeTotalFromLevelAndProgress()
    }

    private func synchronizeTotalFromLevelAndProgress() {
        guard let level64 = Int64(levelField.text ?? ""),
              level64 >= 0,
              level64 <= Int64(BedrockPlayerExperience.maximumLevel) else { return }
        let experience = BedrockPlayerExperience(level: Int32(level64), progress: progressSlider.value)
        isSynchronizing = true
        totalField.text = String(experience.total)
        isSynchronizing = false
    }

    @objc private func save() {
        view.endEditing(true)

        let experience: BedrockPlayerExperience
        switch editSource {
        case .total:
            guard let total = Int64(totalField.text ?? "") else {
                showError(MCBEEditorError.malformedData("经验总数必须是整数"), title: "经验错误")
                return
            }
            do {
                experience = try BedrockPlayerExperience.fromTotal(total)
            } catch {
                showError(error, title: "经验错误")
                return
            }
        case .levelAndProgress:
            guard let level64 = Int64(levelField.text ?? ""),
                  level64 >= 0,
                  level64 <= Int64(BedrockPlayerExperience.maximumLevel) else {
                showError(MCBEEditorError.malformedData("经验等级必须是 0～\(BedrockPlayerExperience.maximumLevel) 的整数"), title: "经验错误")
                return
            }
            experience = BedrockPlayerExperience(level: Int32(level64), progress: progressSlider.value)
        }

        apply(experience)
        let overlay = showBusy("保存玩家经验…")
        workQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.store.save(experience, for: self.record.player)
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.session.invalidateAfterExternalChange()
                    self.completion()
                    self.navigationItem.prompt = "已保存"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.navigationItem.prompt = nil }
                }
            } catch {
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.showError(error, title: "保存经验失败")
                }
            }
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
