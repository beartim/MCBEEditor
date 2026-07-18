import UIKit

final class WorldCommandViewController: UIViewController, UITextFieldDelegate {
    private let session: WorldSession
    private let executor: WorldCommandExecutor
    private let queue = DispatchQueue(label: "com.wzn.blocktopograph.world-command", qos: .userInitiated)

    private let terminalContainer = UIView()
    private let outputView = UITextView()
    private let inputField = UITextField()
    private let inputContainer = UIView()
    private let inputScrollView = UIScrollView()
    private let promptLabel = UILabel()
    private let typedTextLabel = UILabel()
    private let cursorView = UIView()
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startCursorBlinking()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureNavigation()
        configureViews()
        configureLayout()
        startCursorBlinking()
        appendOutput(
            "Blocktopograph 世界命令行\n输入 help 查看全部命令。维度名称：overworld、nether、the_end。"
        )
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
        outputView.isEditable = false
        outputView.isSelectable = true
        outputView.alwaysBounceVertical = true
        outputView.keyboardDismissMode = .interactive
        outputView.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminalContainer.backgroundColor = terminalBackgroundColor
        terminalContainer.layer.cornerRadius = 10
        terminalContainer.clipsToBounds = true

        outputView.backgroundColor = .clear
        outputView.textColor = UIColor(white: 0.92, alpha: 1)
        outputView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)

        inputContainer.backgroundColor = .clear
        inputContainer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(focusCommandInput)))
        inputContainer.accessibilityLabel = "命令输入"
        inputContainer.accessibilityTraits = .allowsDirectInteraction

        inputScrollView.showsHorizontalScrollIndicator = false
        inputScrollView.alwaysBounceHorizontal = true
        inputScrollView.keyboardDismissMode = .none

        let font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        promptLabel.text = ">\u{00A0}"
        promptLabel.font = font
        promptLabel.textColor = UIColor(white: 0.58, alpha: 1)
        promptLabel.setContentHuggingPriority(.required, for: .horizontal)

        typedTextLabel.font = font
        typedTextLabel.textColor = UIColor(white: 0.96, alpha: 1)
        typedTextLabel.numberOfLines = 1
        typedTextLabel.lineBreakMode = .byClipping
        typedTextLabel.text = ""
        typedTextLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        cursorView.backgroundColor = UIColor(white: 0.94, alpha: 1)
        cursorView.layer.cornerRadius = 1
        cursorView.setContentHuggingPriority(.required, for: .horizontal)

        inputField.delegate = self
        inputField.autocapitalizationType = .none
        inputField.autocorrectionType = .no
        inputField.spellCheckingType = .no
        inputField.returnKeyType = .send
        inputField.keyboardType = .asciiCapable
        inputField.smartDashesType = .no
        inputField.smartQuotesType = .no
        inputField.smartInsertDeleteType = .no
        inputField.textContentType = nil
        inputField.addTarget(self, action: #selector(inputChanged), for: .editingChanged)
        // Keep a real UITextField in the hierarchy for keyboard input and selection,
        // while the terminal line mirrors every character in a stable monospaced view.
        inputField.alpha = 0.01
        inputField.tintColor = .clear
        inputField.textColor = .clear
        inputField.backgroundColor = .clear
        inputField.accessibilityElementsHidden = true

        executeButton.setTitle("运行", for: .normal)
        executeButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        executeButton.layer.cornerRadius = 9
        executeButton.backgroundColor = .secondarySystemBackground
        executeButton.addTarget(self, action: #selector(runCommand), for: .touchUpInside)
        executeButton.isEnabled = false
    }

    private var terminalBackgroundColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.025, alpha: 1)
                : UIColor(white: 0.08, alpha: 1)
        }
    }

    private func configureLayout() {
        let terminalLine = UIStackView(arrangedSubviews: [promptLabel, typedTextLabel, cursorView])
        terminalLine.axis = .horizontal
        terminalLine.alignment = .center
        terminalLine.spacing = 0
        terminalLine.translatesAutoresizingMaskIntoConstraints = false
        inputScrollView.addSubview(terminalLine)

        inputScrollView.translatesAutoresizingMaskIntoConstraints = false
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.translatesAutoresizingMaskIntoConstraints = false
        outputView.translatesAutoresizingMaskIntoConstraints = false
        terminalContainer.addSubview(outputView)
        terminalContainer.addSubview(inputContainer)
        inputContainer.addSubview(inputScrollView)
        inputContainer.addSubview(inputField)

        NSLayoutConstraint.activate([
            terminalLine.leadingAnchor.constraint(equalTo: inputScrollView.contentLayoutGuide.leadingAnchor, constant: 12),
            terminalLine.trailingAnchor.constraint(equalTo: inputScrollView.contentLayoutGuide.trailingAnchor, constant: -12),
            terminalLine.topAnchor.constraint(equalTo: inputScrollView.contentLayoutGuide.topAnchor),
            terminalLine.bottomAnchor.constraint(equalTo: inputScrollView.contentLayoutGuide.bottomAnchor),
            terminalLine.heightAnchor.constraint(equalTo: inputScrollView.frameLayoutGuide.heightAnchor),
            cursorView.widthAnchor.constraint(equalToConstant: 8),
            cursorView.heightAnchor.constraint(equalToConstant: 18),

            inputContainer.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor),
            inputContainer.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor),
            inputContainer.topAnchor.constraint(equalTo: terminalContainer.topAnchor),
            inputContainer.heightAnchor.constraint(equalToConstant: 42),

            outputView.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor),
            outputView.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor),
            outputView.topAnchor.constraint(equalTo: inputContainer.bottomAnchor),
            outputView.bottomAnchor.constraint(equalTo: terminalContainer.bottomAnchor),

            inputScrollView.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor),
            inputScrollView.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor),
            inputScrollView.topAnchor.constraint(equalTo: inputContainer.topAnchor),
            inputScrollView.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor),

            inputField.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor),
            inputField.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor),
            inputField.widthAnchor.constraint(equalToConstant: 1),
            inputField.heightAnchor.constraint(equalToConstant: 1)
        ])

        executeButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let stack = UIStackView(arrangedSubviews: [terminalContainer, executeButton])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        ])
    }

    private func startCursorBlinking() {
        cursorView.layer.removeAnimation(forKey: "terminal-cursor-blink")
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.08
        animation.duration = 0.55
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        cursorView.layer.add(animation, forKey: "terminal-cursor-blink")
    }

    @objc private func focusCommandInput() {
        guard !running else { return }
        inputField.becomeFirstResponder()
    }

    @objc private func inputChanged() {
        typedTextLabel.text = visibleTerminalInput(inputField.text ?? "")
        executeButton.isEnabled = !running && !currentInput.isEmpty
        view.layoutIfNeeded()
        let rightEdge = CGPoint(
            x: max(0, inputScrollView.contentSize.width - inputScrollView.bounds.width),
            y: 0
        )
        inputScrollView.setContentOffset(rightEdge, animated: false)
    }

    private func visibleTerminalInput(_ value: String) -> String {
        // UILabel may collapse trailing ordinary spaces when calculating its
        // intrinsic width. Non-breaking spaces keep every typed blank visible
        // and move the block cursor by exactly one monospaced character.
        value.replacingOccurrences(of: " ", with: "\u{00A0}")
            .replacingOccurrences(of: "\t", with: "\u{00A0}\u{00A0}\u{00A0}\u{00A0}")
    }

    private var currentInput: String {
        inputField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    @objc private func clearTerminal() {
        outputView.textStorage.setAttributedString(NSAttributedString())
    }

    @objc private func runCommand() {
        guard !running, !currentInput.isEmpty else { return }
        let raw = currentInput
        inputField.text = ""
        typedTextLabel.text = ""
        appendOutput("\n> \(raw)")
        setRunning(true)

        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let parsed = try WorldCommandParser.parse(raw)
                let result = try self.executor.execute(parsed)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    // WorldSession notifications synchronously update UIKit observers.
                    // Invalidation must therefore happen on the main thread and only
                    // after the command store has finished and released its DB work.
                    if result.changedWorld {
                        self.session.notifyAfterDatabaseMutation()
                    }
                    self.appendOutput(result.message, color: .systemGreen)
                    self.setRunning(false)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.appendOutput("错误：\(error.localizedDescription)", color: .systemRed)
                    self.setRunning(false)
                }
            }
        }
    }

    private func setRunning(_ value: Bool) {
        running = value
        inputField.isEnabled = !value
        inputContainer.alpha = value ? 0.62 : 1
        executeButton.setTitle(value ? "运行中…" : "运行", for: .normal)
        executeButton.isEnabled = !value && !currentInput.isEmpty
        navigationItem.prompt = value ? "正在修改世界，请勿同时打开 Minecraft" : nil
    }

    private func appendOutput(_ text: String, color: UIColor? = nil) {
        let prefix = outputView.textStorage.length == 0 ? "" : "\n"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: outputView.font ?? UIFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: color ?? outputView.textColor ?? UIColor(white: 0.92, alpha: 1)
        ]
        outputView.textStorage.append(NSAttributedString(string: prefix + text, attributes: attributes))
        let end = NSRange(location: outputView.textStorage.length, length: 0)
        outputView.scrollRangeToVisible(end)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        runCommand()
        return false
    }
}
