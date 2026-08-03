import UIKit

/// Per-controller, in-memory viewed-state tracker. The state is intentionally
/// not persisted: refreshing the owning list should call `reset()`, and leaving
/// the controller naturally discards the tracker.
final class ViewedItemTracker {
  private var keys = Set<String>()

  func contains(_ key: String) -> Bool { keys.contains(key) }

  @discardableResult
  func mark(_ key: String) -> Bool { keys.insert(key).inserted }

  @discardableResult
  func clear(_ key: String) -> Bool { keys.remove(key) != nil }

  func reset() { keys.removeAll(keepingCapacity: true) }
}

private final class ViewedBadgeButton: UIButton {
  var handler: (() -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    addTarget(self, action: #selector(tapped), for: .touchUpInside)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  @objc private func tapped() { handler?() }
}

enum ViewedListSupport {
  static func configure(
    cell: UITableViewCell,
    isViewed: Bool,
    showsDisclosure: Bool = true,
    clearAction: @escaping () -> Void
  ) {
    cell.accessoryType = .none

    let stack = UIStackView()
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 10

    if isViewed {
      let badge = ViewedBadgeButton(type: .system)
      badge.setTitle("已查看", for: .normal)
      badge.setTitleColor(.white, for: .normal)
      badge.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
      badge.backgroundColor = UIColor(red: 1.0, green: 0.70, blue: 0.0, alpha: 1.0)
      badge.layer.cornerRadius = 7
      badge.contentEdgeInsets = UIEdgeInsets(top: 6, left: 13, bottom: 6, right: 13)
      badge.accessibilityLabel = "已查看，点按可清除此查看"
      badge.handler = clearAction
      stack.addArrangedSubview(badge)
    }

    if showsDisclosure {
      let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
      chevron.tintColor = .tertiaryLabel
      chevron.contentMode = .scaleAspectFit
      chevron.setContentHuggingPriority(.required, for: .horizontal)
      chevron.widthAnchor.constraint(equalToConstant: 10).isActive = true
      chevron.heightAnchor.constraint(equalToConstant: 18).isActive = true
      stack.addArrangedSubview(chevron)
    }

    cell.accessoryView = stack.arrangedSubviews.isEmpty ? nil : stack
  }

  static func clearAccessory(_ cell: UITableViewCell) {
    cell.accessoryView = nil
  }

  static func presentClearConfirmation(
    from controller: UIViewController,
    onClear: @escaping () -> Void
  ) {
    let alert = UIAlertController(
      title: "清除此查看",
      message: "清除后，该项目会恢复为未查看状态。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "清除", style: .destructive) { _ in onClear() })
    controller.present(alert, animated: true)
  }
}
