import UIKit

extension UIViewController {
    func presentError(_ error: Error, title: String = "操作失败") {
        let alert = UIAlertController(title: title, message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    func showError(_ error: Error, title: String = "操作失败") {
        presentError(error, title: title)
    }

    @discardableResult
    func showBusy(_ message: String = "处理中…") -> UIView {
        let overlay = UIView(frame: view.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.78)
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.startAnimating()
        let label = UILabel()
        label.text = message
        label.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor)
        ])
        view.addSubview(overlay)
        return overlay
    }

    func setBusy(_ busy: Bool, message: String = "处理中…") {
        let tag = 9_981_734
        if busy {
            guard view.viewWithTag(tag) == nil else { return }
            let overlay = showBusy(message)
            overlay.tag = tag
        } else {
            view.viewWithTag(tag)?.removeFromSuperview()
        }
    }
}
