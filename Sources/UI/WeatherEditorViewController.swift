import UIKit

final class WeatherEditorViewController: UIViewController, UITextFieldDelegate {
    private let session: WorldSession
    private let store: WeatherStore
    private let workQueue = DispatchQueue(label: "com.wzn.blocktopograph.weather", qos: .userInitiated)

    private let stack = UIStackView()
    private let conditionLabel = UILabel()
    private let rainSlider = UISlider()
    private let rainValueLabel = UILabel()
    private let rainTimeField = UITextField()
    private let lightningSlider = UISlider()
    private let lightningValueLabel = UILabel()
    private let lightningTimeField = UITextField()

    init(session: WorldSession) {
        self.session = session
        self.store = WeatherStore(session: session)
        super.init(nibName: nil, bundle: nil)
        title = "天气"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save))
        configureUI()
        loadWeather()
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

        conditionLabel.font = .preferredFont(forTextStyle: .title2)
        conditionLabel.numberOfLines = 0
        stack.addArrangedSubview(conditionLabel)

        let presets = UIStackView()
        presets.axis = .horizontal
        presets.spacing = 8
        presets.distribution = .fillEqually
        presets.addArrangedSubview(presetButton(title: "晴朗", action: #selector(setClear)))
        presets.addArrangedSubview(presetButton(title: "下雨", action: #selector(setRain)))
        presets.addArrangedSubview(presetButton(title: "雷暴", action: #selector(setThunder)))
        stack.addArrangedSubview(presets)

        rainSlider.minimumValue = 0
        rainSlider.maximumValue = 1
        rainSlider.addTarget(self, action: #selector(levelChanged), for: .valueChanged)
        lightningSlider.minimumValue = 0
        lightningSlider.maximumValue = 1
        lightningSlider.addTarget(self, action: #selector(levelChanged), for: .valueChanged)

        rainTimeField.borderStyle = .roundedRect
        rainTimeField.keyboardType = .numberPad
        rainTimeField.delegate = self
        lightningTimeField.borderStyle = .roundedRect
        lightningTimeField.keyboardType = .numberPad
        lightningTimeField.delegate = self

        stack.addArrangedSubview(sectionTitle("降雨"))
        stack.addArrangedSubview(sliderRow(slider: rainSlider, valueLabel: rainValueLabel))
        stack.addArrangedSubview(fieldRow(title: "剩余时间（游戏刻）", field: rainTimeField))
        stack.addArrangedSubview(sectionTitle("雷暴"))
        stack.addArrangedSubview(sliderRow(slider: lightningSlider, valueLabel: lightningValueLabel))
        stack.addArrangedSubview(fieldRow(title: "剩余时间（游戏刻）", field: lightningTimeField))

        let note = UILabel()
        note.font = .preferredFont(forTextStyle: .footnote)
        note.textColor = .secondaryLabel
        note.numberOfLines = 0
        note.text = "等级范围为 0～1。20 游戏刻约为 1 秒。修改前请确保 Minecraft 已完全退出；保存时只更新 level.dat 中 rainLevel、rainTime、lightningLevel 和 lightningTime。"
        stack.addArrangedSubview(note)
    }

    private func sectionTitle(_ title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .headline)
        return label
    }

    private func presetButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.backgroundColor = .secondarySystemGroupedBackground
        button.layer.cornerRadius = 9
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func sliderRow(slider: UISlider, valueLabel: UILabel) -> UIStackView {
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        valueLabel.textAlignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 58).isActive = true
        let row = UIStackView(arrangedSubviews: [slider, valueLabel])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        return row
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

    private func loadWeather() {
        let overlay = showBusy("读取天气数据…")
        workQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let settings = try self.store.read()
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.apply(settings)
                }
            } catch {
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.showError(error, title: "读取天气失败")
                }
            }
        }
    }

    private func apply(_ settings: BedrockWeatherSettings) {
        rainSlider.value = settings.rainLevel
        rainTimeField.text = String(settings.rainTime)
        lightningSlider.value = settings.lightningLevel
        lightningTimeField.text = String(settings.lightningTime)
        updateLabels()
    }

    @objc private func setClear() {
        rainSlider.value = 0
        lightningSlider.value = 0
        rainTimeField.text = "12000"
        lightningTimeField.text = "12000"
        updateLabels()
    }

    @objc private func setRain() {
        rainSlider.value = 1
        lightningSlider.value = 0
        rainTimeField.text = "12000"
        lightningTimeField.text = "12000"
        updateLabels()
    }

    @objc private func setThunder() {
        rainSlider.value = 1
        lightningSlider.value = 1
        rainTimeField.text = "12000"
        lightningTimeField.text = "12000"
        updateLabels()
    }

    @objc private func levelChanged() { updateLabels() }

    private func updateLabels() {
        rainValueLabel.text = String(format: "%.0f%%", rainSlider.value * 100)
        lightningValueLabel.text = String(format: "%.0f%%", lightningSlider.value * 100)
        let condition = lightningSlider.value > 0.01 ? "雷暴" : (rainSlider.value > 0.01 ? "下雨" : "晴朗")
        conditionLabel.text = "当前设置：\(condition)"
    }

    @objc private func save() {
        view.endEditing(true)
        guard let rainTime64 = Int64(rainTimeField.text ?? ""), rainTime64 >= 0, rainTime64 <= Int64(Int32.max),
              let lightningTime64 = Int64(lightningTimeField.text ?? ""), lightningTime64 >= 0, lightningTime64 <= Int64(Int32.max) else {
            showError(BlocktopographError.malformedData("天气时间必须是 0～\(Int32.max) 的整数"), title: "时间错误")
            return
        }
        let settings = BedrockWeatherSettings(
            rainLevel: rainSlider.value,
            rainTime: Int32(rainTime64),
            lightningLevel: lightningSlider.value,
            lightningTime: Int32(lightningTime64)
        )
        let overlay = showBusy("保存天气数据…")
        workQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.store.save(settings)
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.session.invalidateAfterExternalChange()
                    self.navigationItem.prompt = "已保存：\(settings.conditionName)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.navigationItem.prompt = nil }
                }
            } catch {
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.showError(error, title: "保存天气失败")
                }
            }
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
