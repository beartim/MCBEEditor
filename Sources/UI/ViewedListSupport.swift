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

/// A fixed-size accessory container is used instead of assigning a bare
/// UIStackView. UITableView does not always ask an Auto Layout-only accessory
/// view for its fitting size on iOS 13, which could leave the yellow badge with
/// a zero-width frame even though the viewed state had been recorded.
private final class ViewedAccessoryView: UIView {
  private let badge: ViewedBadgeButton?
  private let chevron: UIImageView?
  private let spacing: CGFloat = 10

  init(isViewed: Bool, showsDisclosure: Bool, clearAction: @escaping () -> Void) {
    if isViewed {
      let button = ViewedBadgeButton(type: .system)
      button.setTitle("已查看", for: .normal)
      button.setTitleColor(.white, for: .normal)
      button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
      button.backgroundColor = UIColor(red: 1.0, green: 0.70, blue: 0.0, alpha: 1.0)
      button.layer.cornerRadius = 7
      button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 13, bottom: 6, right: 13)
      button.accessibilityLabel = "已查看，点按可清除此查看"
      button.handler = clearAction
      badge = button
    } else {
      badge = nil
    }

    if showsDisclosure {
      let image = UIImageView(image: UIImage(systemName: "chevron.right"))
      image.tintColor = .tertiaryLabel
      image.contentMode = .scaleAspectFit
      chevron = image
    } else {
      chevron = nil
    }

    super.init(frame: .zero)
    if let badge { addSubview(badge) }
    if let chevron { addSubview(chevron) }
    frame.size = calculatedSize
    isAccessibilityElement = false
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private var calculatedSize: CGSize {
    let badgeSize = badge?.sizeThatFits(CGSize(width: 200, height: 44)) ?? .zero
    let chevronSize = chevron == nil ? CGSize.zero : CGSize(width: 10, height: 18)
    let gap: CGFloat = badge != nil && chevron != nil ? spacing : 0
    return CGSize(
      width: ceil(badgeSize.width + gap + chevronSize.width),
      height: ceil(max(badgeSize.height, chevronSize.height, 32))
    )
  }

  override var intrinsicContentSize: CGSize { calculatedSize }

  override func layoutSubviews() {
    super.layoutSubviews()
    var x: CGFloat = 0
    if let badge {
      let size = badge.sizeThatFits(CGSize(width: 200, height: bounds.height))
      badge.frame = CGRect(
        x: x,
        y: floor((bounds.height - size.height) / 2),
        width: size.width,
        height: size.height
      )
      x = badge.frame.maxX + (chevron == nil ? 0 : spacing)
    }
    if let chevron {
      chevron.frame = CGRect(x: x, y: floor((bounds.height - 18) / 2), width: 10, height: 18)
    }
  }
}

enum ViewedListSupport {
  /// `isEnabled` deliberately defaults to false. Viewed badges are now limited
  /// to the entity browser, map-selection entity/block-entity results and block
  /// search results; legacy call sites therefore fall back to a normal chevron.
  static func configure(
    cell: UITableViewCell,
    isEnabled: Bool = false,
    isViewed: Bool,
    showsDisclosure: Bool = true,
    clearAction: @escaping () -> Void
  ) {
    guard isEnabled else {
      cell.accessoryView = nil
      cell.accessoryType = showsDisclosure ? .disclosureIndicator : .none
      return
    }

    cell.accessoryType = .none
    let accessory = ViewedAccessoryView(
      isViewed: isViewed,
      showsDisclosure: showsDisclosure,
      clearAction: clearAction
    )
    accessory.frame.size = accessory.intrinsicContentSize
    cell.accessoryView = accessory
  }

  static func clearAccessory(_ cell: UITableViewCell) {
    cell.accessoryView = nil
    cell.accessoryType = .none
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
