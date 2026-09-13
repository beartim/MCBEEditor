import UIKit

struct ValidatedSharedWorldCommand {
    let lineNumber: Int
    let rawText: String
    let command: ParsedWorldCommand
}

final class WorldCommandViewController: UIViewController, UITextFieldDelegate {
    private let session: WorldSession
    private let executor: WorldCommandExecutor
    private let queue = DispatchQueue(label: "com.wzn.mcbeeditor.world-command", qos: .userInitiated)

    private lazy var structureFiles = StructureFileCoordinator(presenter: self, session: session)

    private let terminalContainer = UIView()
    private let outputView = UITextView()
    private let inputField = UITextField()
    private let inputContainer = UIView()
    private let inputScrollView = UIScrollView()
    private let promptLabel = UILabel()
    private let typedTextBeforeCursorLabel = UILabel()
    private let typedTextAfterCursorLabel = UILabel()
    private let cursorView = UIView()
    private let executeButton = UIButton(type: .system)
    private lazy var keyboardButton = UIBarButtonItem(
        image: UIImage(systemName: "keyboard"),
        style: .plain,
        target: self,
        action: #selector(toggleKeyboard)
    )
    private lazy var historyUpButton = UIBarButtonItem(
        image: UIImage(systemName: "arrow.up"),
        style: .plain,
        target: self,
        action: #selector(recallPreviousCommand)
    )
    private lazy var historyDownButton = UIBarButtonItem(
        image: UIImage(systemName: "arrow.down"),
        style: .plain,
        target: self,
        action: #selector(recallNextCommand)
    )
    private lazy var caretLeftButton = UIBarButtonItem(
        image: UIImage(systemName: "arrow.left"),
        style: .plain,
        target: self,
        action: #selector(moveCaretLeft)
    )
    private lazy var caretRightButton = UIBarButtonItem(
        image: UIImage(systemName: "arrow.right"),
        style: .plain,
        target: self,
        action: #selector(moveCaretRight)
    )
    private var running = false
    private var commandHistory = [String]()
    private var commandHistoryIndex = -1
    private var commandHistoryDraft = ""

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
    }

    private func configureNavigation() {
        let clearButton = UIBarButtonItem(
            title: "清屏",
            style: .plain,
            target: self,
            action: #selector(clearTerminal)
        )
        keyboardButton.accessibilityLabel = "呼出或收起键盘"
        keyboardButton.accessibilityHint = "切换命令输入键盘的显示状态"
        historyUpButton.accessibilityLabel = "上一条命令"
        historyDownButton.accessibilityLabel = "下一条命令"
        caretLeftButton.accessibilityLabel = "光标左移"
        caretRightButton.accessibilityLabel = "光标右移"
        // rightBarButtonItems 的首项位于最右侧。视觉顺序从左到右为：
        // ↑ ↓ ← → 键盘 清屏。四个方向键位于键盘按钮左侧。
        navigationItem.rightBarButtonItems = [
            clearButton, keyboardButton, caretRightButton, caretLeftButton, historyDownButton, historyUpButton
        ]
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

        for label in [typedTextBeforeCursorLabel, typedTextAfterCursorLabel] {
            label.font = font
            label.textColor = UIColor(white: 0.96, alpha: 1)
            label.numberOfLines = 1
            label.lineBreakMode = .byClipping
            label.text = ""
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }

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
        let terminalLine = UIStackView(arrangedSubviews: [
            promptLabel, typedTextBeforeCursorLabel, cursorView, typedTextAfterCursorLabel
        ])
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

    @objc private func toggleKeyboard() {
        guard !running else { return }
        if inputField.isFirstResponder {
            inputField.resignFirstResponder()
        } else {
            inputField.becomeFirstResponder()
        }
    }

    @objc private func inputChanged() {
        syncVisibleInput()
    }

    func textFieldDidChangeSelection(_ textField: UITextField) {
        syncVisibleInput()
    }

    private func syncVisibleInput() {
        let value = inputField.text ?? ""
        let utf16Text = value as NSString
        let caretOffset: Int
        if let selected = inputField.selectedTextRange {
            caretOffset = inputField.offset(from: inputField.beginningOfDocument, to: selected.start)
        } else {
            caretOffset = utf16Text.length
        }
        let clampedOffset = min(max(0, caretOffset), utf16Text.length)
        typedTextBeforeCursorLabel.text = visibleTerminalInput(utf16Text.substring(to: clampedOffset))
        typedTextAfterCursorLabel.text = visibleTerminalInput(utf16Text.substring(from: clampedOffset))
        executeButton.isEnabled = !running && !currentInput.isEmpty
        view.layoutIfNeeded()
        let cursorRect = cursorView.convert(cursorView.bounds, to: inputScrollView).insetBy(dx: -18, dy: 0)
        inputScrollView.scrollRectToVisible(cursorRect, animated: false)
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

    @objc private func recallPreviousCommand() {
        guard !running, !commandHistory.isEmpty else { return }
        if commandHistoryIndex < 0 {
            commandHistoryDraft = inputField.text ?? ""
            commandHistoryIndex = commandHistory.count - 1
        } else if commandHistoryIndex > 0 {
            commandHistoryIndex -= 1
        }
        setCommandInputText(commandHistory[commandHistoryIndex])
    }

    @objc private func recallNextCommand() {
        guard !running, commandHistoryIndex >= 0 else { return }
        if commandHistoryIndex < commandHistory.count - 1 {
            commandHistoryIndex += 1
            setCommandInputText(commandHistory[commandHistoryIndex])
            return
        }
        commandHistoryIndex = -1
        setCommandInputText(commandHistoryDraft)
    }

    private func rememberCommandHistory(_ text: String) {
        commandHistory.append(text)
        commandHistoryIndex = -1
        commandHistoryDraft = ""
    }

    private func setCommandInputText(_ text: String) {
        inputField.text = text
        if let end = inputField.position(from: inputField.beginningOfDocument, offset: (text as NSString).length) {
            inputField.selectedTextRange = inputField.textRange(from: end, to: end)
        }
        syncVisibleInput()
    }

    @objc private func moveCaretLeft() {
        moveCaret(by: -1)
    }

    @objc private func moveCaretRight() {
        moveCaret(by: 1)
    }

    private func moveCaret(by delta: Int) {
        guard !running else { return }
        let length = ((inputField.text ?? "") as NSString).length
        let selection = inputField.selectedTextRange
        let start = selection.map { inputField.offset(from: inputField.beginningOfDocument, to: $0.start) } ?? length
        let end = selection.map { inputField.offset(from: inputField.beginningOfDocument, to: $0.end) } ?? start
        let target: Int
        if start != end {
            target = delta < 0 ? start : end
        } else {
            target = min(max(0, start + delta), length)
        }
        guard let position = inputField.position(from: inputField.beginningOfDocument, offset: target) else { return }
        inputField.selectedTextRange = inputField.textRange(from: position, to: position)
        syncVisibleInput()
    }

    @objc private func clearTerminal() {
        outputView.textStorage.setAttributedString(NSAttributedString())
    }

    @objc private func runCommand() {
        guard !running, !currentInput.isEmpty else { return }
        let raw = currentInput
        rememberCommandHistory(raw)
        inputField.text = ""
        commandHistoryIndex = -1
        commandHistoryDraft = ""
        syncVisibleInput()
        appendOutput("\n> \(raw)")
        setRunning(true)

        do {
            executeParsedCommand(try WorldCommandParser.parse(raw)) { result in
                switch result {
                case .success(let value):
                    if value.changedWorld { self.session.notifyAfterDatabaseMutation() }
                    self.appendResult(value)
                case .failure(let error): self.appendOutput("错误：\(error.localizedDescription)", color: .systemRed)
                }
                self.setRunning(false)
            }
        } catch {
            appendOutput("错误：\(error.localizedDescription)", color: .systemRed)
            setRunning(false)
        }
    }

    /// File commands await their dialogs before a Command.txt batch advances.
    private func executeParsedCommand(_ command: ParsedWorldCommand, completion: @escaping StructureFileCoordinator.Completion) {
        switch command {
        case .structure(.importFile(let name)):
            inputField.resignFirstResponder()
            structureFiles.importFile(named: name, completion: completion)
        case .structure(.exportFile(let format, let name)):
            inputField.resignFirstResponder()
            structureFiles.exportFile(format: format, named: name, completion: completion)
        default:
            queue.async {
                let result = Result { try self.executor.execute(command) }
                DispatchQueue.main.async { completion(result) }
            }
        }
    }

    /// Executes validated lines serially; runtime errors do not stop later lines.
    func executeValidatedSharedCommands(_ commands: [ValidatedSharedWorldCommand], completion: @escaping () -> Void) {
        guard !commands.isEmpty else { completion(); return }
        loadViewIfNeeded()
        guard !running else { completion(); return }
        inputField.resignFirstResponder()
        setRunning(true)
        appendOutput("[Command.txt] 开始执行，共 \(commands.count) 条命令。", color: .systemBlue)
        var changedWorld = false
        var failureCount = 0
        func next(_ index: Int) {
            guard index < commands.count else {
                if changedWorld { self.session.notifyAfterDatabaseMutation() }
                let summary = failureCount == 0
                    ? "[Command.txt] 全部命令执行完成。"
                    : "[Command.txt] 执行完成：\(failureCount) 条命令发生运行时错误，其余命令已继续执行。"
                self.appendOutput(summary, color: failureCount == 0 ? .systemGreen : .systemRed)
                self.setRunning(false)
                completion()
                return
            }
            let item = commands[index]
            self.appendOutput("[第 \(item.lineNumber) 行] > \(item.rawText)")
            self.executeParsedCommand(item.command) { result in
                switch result {
                case .success(let value):
                    changedWorld = changedWorld || value.changedWorld
                    self.appendResult(value)
                case .failure(let error):
                    failureCount += 1
                    self.appendOutput("错误：\(error.localizedDescription)", color: .systemRed)
                }
                DispatchQueue.main.async { next(index + 1) }
            }
        }
        next(0)
    }

    private func setRunning(_ value: Bool) {
        running = value
        inputField.isEnabled = !value
        inputContainer.alpha = value ? 0.62 : 1
        executeButton.setTitle(value ? "运行中…" : "运行", for: .normal)
        executeButton.isEnabled = !value && !currentInput.isEmpty
        historyUpButton.isEnabled = !value
        historyDownButton.isEnabled = !value
        caretLeftButton.isEnabled = !value
        caretRightButton.isEnabled = !value
        keyboardButton.isEnabled = !value
        navigationItem.prompt = value ? "正在执行命令…" : nil
    }

    private func outputColor(for style: WorldCommandOutputStyle) -> UIColor {
        switch style {
        case .success, .entity: return .systemGreen
        case .localPlayer: return .systemYellow
        case .onlinePlayer: return .systemBlue
        case .block: return .systemBlue
        case .blockEntity: return .systemPurple
        }
    }

    private func appendResult(_ result: WorldCommandExecutionResult) {
        if result.outputLines.isEmpty {
            appendOutput(result.message, color: .systemGreen)
            return
        }
        // One layout/scroll per result, even for a query listing thousands of
        // chunks. Every line retains its original text, order and colour.
        outputView.textStorage.beginEditing()
        for line in result.outputLines {
            appendOutput(line.text, color: outputColor(for: line.style), scroll: false)
        }
        outputView.textStorage.endEditing()
        scrollOutputToEnd()
    }

    private func appendOutput(_ text: String, color: UIColor? = nil, scroll: Bool = true) {
        let prefix = outputView.textStorage.length == 0 ? "" : "\n"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: outputView.font ?? UIFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: color ?? outputView.textColor ?? UIColor(white: 0.92, alpha: 1)
        ]
        outputView.textStorage.append(NSAttributedString(string: prefix + text, attributes: attributes))
        if scroll { scrollOutputToEnd() }
    }

    private func scrollOutputToEnd() {
        let end = NSRange(location: outputView.textStorage.length, length: 0)
        outputView.scrollRangeToVisible(end)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        runCommand()
        return false
    }
}
