import UIKit

final class DatabaseValueViewController: UIViewController {
    private let valueData: Data
    private let editable: Bool
    private let textView = UITextView()

    init(title: String, data: Data, editable: Bool) {
        self.valueData = data
        self.editable = editable
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = editable
        textView.alwaysBounceVertical = true
        textView.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.text = Self.describe(valueData)
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareRawData)),
            UIBarButtonItem(title: "复制", style: .plain, target: self, action: #selector(copyDescription))
        ]
    }

    @objc private func copyDescription() {
        UIPasteboard.general.string = textView.text
        navigationItem.prompt = "已复制文本与十六进制内容"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.navigationItem.prompt = nil }
    }

    @objc private func shareRawData() {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("mcbeeditor-value-\(UUID().uuidString.prefix(8)).bin")
        do {
            try valueData.write(to: output, options: .atomic)
            let activity = UIActivityViewController(activityItems: [output], applicationActivities: nil)
            activity.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
            present(activity, animated: true)
        } catch {
            showError(error, title: "导出原始值失败")
        }
    }

    private static func describe(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8),
           text.unicodeScalars.allSatisfy(Self.isDisplayableTextScalar) {
            return "UTF-8 (\(data.count) bytes)\n\n\(text)\n\nHEX\n\(data.hexDump())"
        }
        return "Binary (\(data.count) bytes)\n\n\(data.hexDump())"
    }

    private static func isDisplayableTextScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09, 0x0A, 0x0D:
            return true
        default:
            return !CharacterSet.controlCharacters.contains(scalar)
        }
    }
}
