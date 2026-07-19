import UIKit

final class TimeEditorViewController: UIViewController, UITextFieldDelegate {
    private let session: WorldSession
    private let workQueue = DispatchQueue(label: "com.wzn.blocktopograph.time", qos: .userInitiated)

    private let stack = UIStackView()
    private let summaryLabel = UILabel()
    private let dayLabel = UILabel()
    private let timeField = UITextField()
    private let automaticProgressionSwitch = UISwitch()

    init(session: WorldSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
        title = "时间"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save))
        configureUI()
        loadTime()
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

        summaryLabel.font = .preferredFont(forTextStyle: .title2)
        summaryLabel.numberOfLines = 0
        stack.addArrangedSubview(summaryLabel)

        dayLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        dayLabel.textColor = .secondaryLabel
        stack.addArrangedSubview(dayLabel)

        timeField.borderStyle = .roundedRect
        timeField.keyboardType = .numbersAndPunctuation
        timeField.delegate = self
        timeField.addTarget(self, action: #selector(timeTextChanged), for: .editingChanged)
        stack.addArrangedSubview(fieldRow(title: "游戏 time", field: timeField))
        stack.addArrangedSubview(switchRow(title: "时间自动流逝", control: automaticProgressionSwitch))

        stack.addArrangedSubview(sectionTitle("快速设定当前天的时间"))
        let firstRow = UIStackView(arrangedSubviews: [
            presetButton(title: "白天", tick: 0),
            presetButton(title: "中午", tick: 6_000),
            presetButton(title: "日落", tick: 12_001)
        ])
        firstRow.axis = .horizontal
        firstRow.spacing = 8
        firstRow.distribution = .fillEqually
        stack.addArrangedSubview(firstRow)

        let secondRow = UIStackView(arrangedSubviews: [
            presetButton(title: "夜晚", tick: 13_801),
            presetButton(title: "午夜", tick: 18_000),
            presetButton(title: "日出", tick: 22_201)
        ])
        secondRow.axis = .horizontal
        secondRow.spacing = 8
        secondRow.distribution = .fillEqually
        stack.addArrangedSubview(secondRow)

        let note = UILabel()
        note.font = .preferredFont(forTextStyle: .footnote)
        note.textColor = .secondaryLabel
        note.numberOfLines = 0
        note.text = "白天 0～12000；日落 12001～13800；夜晚 13801～22200；日出 22201～23999。24000 等价于下一天的 0。时间自动流逝对应 level.dat 的 dodaylightcycle。"
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
        field.textAlignment = .right
        let row = UIStackView(arrangedSubviews: [label, field])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        return row
    }

    private func switchRow(title: String, control: UISwitch) -> UIStackView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)
        let row = UIStackView(arrangedSubviews: [label, control])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.distribution = .equalSpacing
        return row
    }

    private func presetButton(title: String, tick: Int64) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.backgroundColor = .secondarySystemGroupedBackground
        button.layer.cornerRadius = 9
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 6, bottom: 10, right: 6)
        button.tag = Int(tick)
        button.addTarget(self, action: #selector(applyPreset(_:)), for: .touchUpInside)
        return button
    }

    private func loadTime() {
        let overlay = showBusy("读取时间数据…")
        workQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let settings = try BedrockTimeStore.read(session: self.session)
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.apply(settings)
                }
            } catch {
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.showError(error, title: "读取时间失败")
                }
            }
        }
    }

    private func apply(_ settings: BedrockTimeSettings) {
        timeField.text = String(settings.time)
        automaticProgressionSwitch.isOn = settings.automaticProgression
        updateSummary()
    }

    @objc private func timeTextChanged() { updateSummary() }

    private func updateSummary() {
        guard let time = Int64(timeField.text ?? "") else {
            summaryLabel.text = "请输入 Int64 游戏刻"
            dayLabel.text = nil
            return
        }
        summaryLabel.text = BedrockTimeStore.daytimeSummary(time)
        dayLabel.text = "day=\(BedrockTimeStore.floorDivision(time, by: 24_000)) · gametime=\(time)"
    }

    @objc private func applyPreset(_ sender: UIButton) {
        guard let current = Int64(timeField.text ?? "") else { return }
        let day = BedrockTimeStore.floorDivision(current, by: 24_000)
        let (base, overflow) = day.multipliedReportingOverflow(by: 24_000)
        guard !overflow else { return }
        let (updated, addOverflow) = base.addingReportingOverflow(Int64(sender.tag))
        guard !addOverflow else { return }
        timeField.text = String(updated)
        updateSummary()
    }

    @objc private func save() {
        view.endEditing(true)
        guard let time = Int64(timeField.text ?? "") else {
            showError(BlocktopographError.malformedData("time 必须是 Int64 整数"), title: "时间错误")
            return
        }
        let settings = BedrockTimeSettings(time: time, automaticProgression: automaticProgressionSwitch.isOn)
        let overlay = showBusy("保存时间数据…")
        workQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try BedrockTimeStore.save(settings, session: self.session)
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.session.invalidateAfterExternalChange()
                    self.navigationItem.prompt = "已保存 time=\(time)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.navigationItem.prompt = nil }
                }
            } catch {
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.showError(error, title: "保存时间失败")
                }
            }
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
