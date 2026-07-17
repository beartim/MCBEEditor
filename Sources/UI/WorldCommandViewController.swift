import UIKit

final class WorldCommandViewController: UIViewController, UITextFieldDelegate {
    private let session: WorldSession
    private let executor: WorldCommandExecutor
    private let queue = DispatchQueue(label: "com.wzn.blocktopograph.world-command", qos: .userInitiated)

    private let dimensionControl = UISegmentedControl(items: BedrockDimension.allCases.map(\.displayName))
    private let outputView = UITextView()
    private let inputField = UITextField()
    private let executeButton = UIButton(type: .system)
    private var running = false

    init(session: WorldSession) {
        self.session = session
        self.executor = WorldCommandExecutor(session: session)
        super.init(nibName: nil, bundle: nil)
        title = "命令"
        tabBarItem = UITabBarItem(title: "命令", image: UIImage(systemName: "terminal"), tag: 4)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureNavigation()
        configureViews()
        configureLayout()
        appendOutput("Blocktopograph 世界命令行\n输入 help 查看全部命令。clone 与 fill 使用上方选择的维度。")
    }

    private func configureNavigation() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "清屏",
            style: .plain,
            target: self,
            action: #selector(clearTerminal)
        )
    }

    private func configureViews() {
        dimensionControl.selectedSegmentIndex = 0
        dimensionControl.accessibilityLabel = "命令操作维度"

        outputView.isEditable = false
        outputView.isSelectable = true
        outputView.alwaysBounceVertical = true
        outputView.keyboardDismissMode = .interactive
        outputView.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        outputView.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(white: 0.04, alpha: 1) : UIColor(white: 0.08, alpha: 1)
        }
        outputView.textColor = UIColor(white: 0.92, alpha: 1)
        outputView.layer.cornerRadius = 10
        outputView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)

        inputField.delegate = self
        inputField.placeholder = "输入命令（不需要 /）"
        inputField.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        inputField.borderStyle = .roundedRect
        inputField.autocapitalizationType = .none
        inputField.autocorrectionType = .no
        inputField.spellCheckingType = .no
        inputField.returnKeyType = .send
        inputField.clearButtonMode = .whileEditing
        inputField.addTarget(self, action: #selector(inputChanged), for: .editingChanged)

        executeButton.setTitle("运行", for: .normal)
        executeButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        executeButton.layer.cornerRadius = 9
        executeButton.backgroundColor = .secondarySystemBackground
        executeButton.addTarget(self, action: #selector(runCommand), for: .touchUpInside)
        executeButton.isEnabled = false
    }

    private func configureLayout() {
        let inputRow = UIStackView(arrangedSubviews: [inputField, executeButton])
        inputRow.axis = .horizontal
        inputRow.spacing = 8
        inputRow.alignment = .fill
        executeButton.widthAnchor.constraint(equalToConstant: 72).isActive = true

        let stack = UIStackView(arrangedSubviews: [dimensionControl, outputView, inputRow])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            inputRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    @objc private func inputChanged() {
        executeButton.isEnabled = !running && !(inputField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    @objc private func clearTerminal() {
        outputView.text = ""
    }

    @objc private func runCommand() {
        guard !running,
              let raw = inputField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return }
        let dimension = BedrockDimension.allCases.indices.contains(dimensionControl.selectedSegmentIndex)
            ? BedrockDimension.allCases[dimensionControl.selectedSegmentIndex].rawValue
            : 0
        inputField.text = ""
        inputField.resignFirstResponder()
        appendOutput("\n> \(raw)")
        setRunning(true)

        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let parsed = try WorldCommandParser.parse(raw)
                let result = try self.executor.execute(parsed, dimension: dimension)
                DispatchQueue.main.async {
                    self.appendOutput(result.message)
                    self.setRunning(false)
                }
            } catch {
                DispatchQueue.main.async {
                    self.appendOutput("错误：\(error.localizedDescription)")
                    self.setRunning(false)
                }
            }
        }
    }

    private func setRunning(_ value: Bool) {
        running = value
        inputField.isEnabled = !value
        dimensionControl.isEnabled = !value
        executeButton.setTitle(value ? "运行中…" : "运行", for: .normal)
        executeButton.isEnabled = !value && !(inputField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        navigationItem.prompt = value ? "正在修改世界，请勿同时打开 Minecraft" : nil
    }

    private func appendOutput(_ text: String) {
        if outputView.text.isEmpty { outputView.text = text }
        else { outputView.text += "\n\(text)" }
        let end = NSRange(location: max(0, outputView.text.utf16.count - 1), length: 1)
        outputView.scrollRangeToVisible(end)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        runCommand()
        return true
    }
}
