import UIKit

/// A tree-aware NBT cell whose icon and text share the same indentation and
/// horizontal scrolling surface. Deep/long nodes can therefore be revealed by
/// swiping left before UITableView exposes destructive trailing actions.
private final class NBTTreeHorizontalScrollView: UIScrollView {
  /// When the hidden suffix has already been revealed, fail the next
  /// leftward pan at gesture-begin time so the parent UITableView can take
  /// that *new* gesture and reveal its trailing actions. A rightward pan is
  /// still accepted, so the user can scroll the NBT row back toward its icon.
  override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    if gestureRecognizer === panGestureRecognizer {
      let maximumOffset = max(0, contentSize.width - bounds.width)
      let velocity = panGestureRecognizer.velocity(in: self)
      if maximumOffset > 1,
        contentOffset.x >= maximumOffset - 1,
        velocity.x < 0
      {
        return false
      }
    }
    return super.gestureRecognizerShouldBegin(gestureRecognizer)
  }
}

final class NBTTreeCell: UITableViewCell, UIScrollViewDelegate {
  struct HierarchyLine {
    enum Kind { case start, continuation, end }
    let ancestorDepth: Int
    let kind: Kind
  }

  private let horizontalScrollView = NBTTreeHorizontalScrollView()
  private let scrollingContentView = UIView()
  private lazy var rowTapGesture: UITapGestureRecognizer = {
    let gesture = UITapGestureRecognizer(target: self, action: #selector(handleRowTap(_:)))
    gesture.cancelsTouchesInView = true
    return gesture
  }()
  private let hierarchyLayer = CAShapeLayer()
  private let iconView = UIImageView()
  private let titleNodeLabel = UILabel()
  private let detailNodeLabel = UILabel()

  private var depth = 0
  private var treeIndentationStep: CGFloat = 18
  private var hierarchyLines: [HierarchyLine] = []
  private var contentLeading: CGFloat = 14
  private var titleText = ""
  private var detailText = ""
  private var titleFont = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
  private var detailFont = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
  private var detailLineCount = 1
  private var lastLaidOutWidth: CGFloat = 0

  var canRevealMoreHorizontally: Bool {
    layoutIfNeeded()
    let maximumOffset = max(0, horizontalScrollView.contentSize.width - horizontalScrollView.bounds.width)
    return maximumOffset > 1 && horizontalScrollView.contentOffset.x < maximumOffset - 1
  }

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: .default, reuseIdentifier: reuseIdentifier)
    preservesSuperviewLayoutMargins = true
    clipsToBounds = true

    horizontalScrollView.showsHorizontalScrollIndicator = true
    horizontalScrollView.showsVerticalScrollIndicator = false
    horizontalScrollView.alwaysBounceHorizontal = false
    horizontalScrollView.alwaysBounceVertical = false
    horizontalScrollView.isDirectionalLockEnabled = true
    horizontalScrollView.delaysContentTouches = false
    horizontalScrollView.canCancelContentTouches = true
    horizontalScrollView.delegate = self
    horizontalScrollView.scrollsToTop = false
    // A UIScrollView inside UITableViewCell owns the touch sequence, which
    // otherwise prevents UITableView from delivering didSelectRowAt. Forward
    // a true tap back to the table while leaving horizontal pans and context
    // menus untouched. This restores single-tap NBT editing/expansion.
    horizontalScrollView.addGestureRecognizer(rowTapGesture)
    contentView.addSubview(horizontalScrollView)
    horizontalScrollView.addSubview(scrollingContentView)

    hierarchyLayer.fillColor = UIColor.clear.cgColor
    hierarchyLayer.strokeColor = UIColor.secondaryLabel.withAlphaComponent(0.48).cgColor
    hierarchyLayer.lineWidth = 1.15
    hierarchyLayer.lineCap = .round
    hierarchyLayer.lineJoin = .round
    hierarchyLayer.contentsScale = UIScreen.main.scale
    scrollingContentView.layer.addSublayer(hierarchyLayer)

    iconView.contentMode = .center
    iconView.clipsToBounds = false
    scrollingContentView.addSubview(iconView)

    titleNodeLabel.numberOfLines = 1
    titleNodeLabel.lineBreakMode = .byClipping
    titleNodeLabel.adjustsFontSizeToFitWidth = false
    scrollingContentView.addSubview(titleNodeLabel)

    detailNodeLabel.textColor = .secondaryLabel
    detailNodeLabel.lineBreakMode = .byClipping
    detailNodeLabel.adjustsFontSizeToFitWidth = false
    scrollingContentView.addSubview(detailNodeLabel)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  @objc private func handleRowTap(_ recognizer: UITapGestureRecognizer) {
    guard recognizer.state == .ended else { return }
    var view: UIView? = self
    while let current = view, !(current is UITableView) { view = current.superview }
    guard let tableView = view as? UITableView,
      let indexPath = tableView.indexPath(for: self),
      let delegate = tableView.delegate
    else { return }

    // The editing controllers deselect immediately in didSelectRowAt, so call
    // the delegate directly instead of relying on UITableView's selection
    // recognizer, which never sees touches captured by the nested scroll view.
    delegate.tableView?(tableView, didSelectRowAt: indexPath)
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    horizontalScrollView.setContentOffset(.zero, animated: false)
    hierarchyLines = []
    hierarchyLayer.path = nil
    iconView.image = nil
    titleNodeLabel.text = nil
    detailNodeLabel.text = nil
  }

  func configure(
    node: NBTNode,
    expanded: Bool,
    searchMode: Bool,
    titleSuffix: String = "",
    indentationWidth: CGFloat = 18,
    titleFont: UIFont = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular),
    detailFont: UIFont = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular),
    detailLineCount: Int? = nil,
    compactLeading: CGFloat? = nil,
    hierarchyLines: [HierarchyLine] = []
  ) {
    self.depth = searchMode ? 0 : node.depth
    self.treeIndentationStep = indentationWidth
    self.titleFont = titleFont
    self.detailFont = detailFont
    self.detailLineCount = detailLineCount ?? (searchMode ? 2 : 1)
    self.contentLeading = compactLeading ?? 14
    self.hierarchyLines = searchMode ? [] : hierarchyLines

    let marker = node.hasChildren ? (expanded ? "▾" : "▸") : " "
    titleText = "\(marker) \(node.name)  <\(node.value.type.displayName)>\(titleSuffix)"
    detailText = searchMode ? "\(node.value.summary)\n\(node.pathDescription)" : node.value.summary

    iconView.image = NBTTagIcon.image(for: node.value.type)
    titleNodeLabel.font = titleFont
    detailNodeLabel.font = detailFont
    detailNodeLabel.numberOfLines = self.detailLineCount
    titleNodeLabel.text = titleText
    detailNodeLabel.text = detailText
    setNeedsLayout()
  }

  func configureCompact(
    node: NBTNode,
    expanded: Bool,
    titleSuffix: String = "",
    indentationWidth: CGFloat,
    titleFont: UIFont,
    detailFont: UIFont,
    hierarchyLines: [HierarchyLine]
  ) {
    depth = node.depth
    self.treeIndentationStep = indentationWidth
    self.titleFont = titleFont
    self.detailFont = detailFont
    detailLineCount = 2
    contentLeading = 8
    self.hierarchyLines = hierarchyLines
    let marker = node.hasChildren ? (expanded ? "▾" : "▸") : " "
    titleText = "\(marker) \(node.name)\(titleSuffix)"
    detailText = "\(node.value.type.displayName) · \(node.value.summary)"
    iconView.image = NBTTagIcon.image(for: node.value.type)
    titleNodeLabel.font = titleFont
    detailNodeLabel.font = detailFont
    detailNodeLabel.numberOfLines = 2
    titleNodeLabel.text = titleText
    detailNodeLabel.text = detailText
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    horizontalScrollView.frame = contentView.bounds
    guard horizontalScrollView.bounds.width > 0, horizontalScrollView.bounds.height > 0 else { return }

    let h = horizontalScrollView.bounds.height
    let iconSize = CGSize(width: 24, height: 24)
    let iconX = contentLeading + CGFloat(depth) * treeIndentationStep
    let iconY = max(3, (h - iconSize.height) / 2)
    let textX = iconX + iconSize.width + 8

    let titleMeasured = (titleText as NSString).size(withAttributes: [.font: titleFont])
    let detailLines = detailText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let detailWidth = detailLines.map {
      ($0 as NSString).size(withAttributes: [.font: detailFont]).width
    }.max() ?? 0
    let desiredTextWidth = max(titleMeasured.width, detailWidth) + 12
    let minimumContentWidth = horizontalScrollView.bounds.width
    let desiredContentWidth = max(minimumContentWidth, textX + desiredTextWidth + 12)
    scrollingContentView.frame = CGRect(x: 0, y: 0, width: desiredContentWidth, height: h)
    horizontalScrollView.contentSize = scrollingContentView.bounds.size

    iconView.frame = CGRect(origin: CGPoint(x: iconX, y: iconY), size: iconSize)
    let availableTextWidth = max(1, desiredContentWidth - textX - 10)
    let titleHeight = min(20, max(17, titleMeasured.height + 1))
    let detailHeight = max(15, min(h - titleHeight - 5, detailFont.lineHeight * CGFloat(max(1, detailLineCount))))
    let totalTextHeight = titleHeight + detailHeight + 1
    let textY = max(2, (h - totalTextHeight) / 2)
    titleNodeLabel.frame = CGRect(x: textX, y: textY, width: availableTextWidth, height: titleHeight)
    detailNodeLabel.frame = CGRect(
      x: textX, y: textY + titleHeight + 1, width: availableTextWidth, height: detailHeight)

    drawHierarchyLines(cellHeight: h, iconCenterY: iconView.frame.midY)

    if lastLaidOutWidth != horizontalScrollView.bounds.width {
      lastLaidOutWidth = horizontalScrollView.bounds.width
      let maxOffset = max(0, horizontalScrollView.contentSize.width - horizontalScrollView.bounds.width)
      if horizontalScrollView.contentOffset.x > maxOffset {
        horizontalScrollView.contentOffset.x = maxOffset
      }
    }
  }

  private func drawHierarchyLines(cellHeight: CGFloat, iconCenterY: CGFloat) {
    let path = UIBezierPath()
    for line in hierarchyLines {
      let ancestorIconX = contentLeading + CGFloat(line.ancestorDepth) * treeIndentationStep + 12
      switch line.kind {
      case .start:
        path.move(to: CGPoint(x: ancestorIconX, y: iconCenterY + 10))
        path.addLine(to: CGPoint(x: ancestorIconX, y: cellHeight))
      case .continuation:
        path.move(to: CGPoint(x: ancestorIconX, y: 0))
        path.addLine(to: CGPoint(x: ancestorIconX, y: cellHeight))
      case .end:
        path.move(to: CGPoint(x: ancestorIconX, y: 0))
        path.addLine(to: CGPoint(x: ancestorIconX, y: iconCenterY))
        let currentIconCenterX = contentLeading + CGFloat(depth) * treeIndentationStep + 12
        path.addLine(to: CGPoint(x: currentIconCenterX - 10, y: iconCenterY))
      }
    }
    hierarchyLayer.frame = scrollingContentView.bounds
    hierarchyLayer.path = path.cgPath
  }
}

enum NBTTreeHierarchyGuide {
  static func lines(
    forRowAt index: Int,
    rows: [NBTNode],
    expanded: Set<[NBTPathComponent]>
  ) -> [NBTTreeCell.HierarchyLine] {
    guard rows.indices.contains(index) else { return [] }
    let node = rows[index]
    var result = [NBTTreeCell.HierarchyLine]()

    if node.hasChildren, expanded.contains(node.path) {
      result.append(.init(ancestorDepth: node.depth, kind: .start))
    }

    guard node.depth > 0 else { return result }
    for ancestorDepth in 0..<node.depth {
      let prefixCount = ancestorDepth + 1
      guard node.path.count >= prefixCount else { continue }
      let ancestorPath = Array(node.path.prefix(prefixCount))
      guard expanded.contains(ancestorPath),
        let parentIndex = rows[..<index].lastIndex(where: { $0.path == ancestorPath })
      else { continue }

      var lastDirectChildIndex: Int?
      var scan = parentIndex + 1
      while rows.indices.contains(scan) {
        let candidate = rows[scan]
        if candidate.depth <= ancestorDepth { break }
        if candidate.depth == ancestorDepth + 1 { lastDirectChildIndex = scan }
        scan += 1
      }
      guard let lastChild = lastDirectChildIndex, index <= lastChild else { continue }
      result.append(
        .init(
          ancestorDepth: ancestorDepth,
          kind: index == lastChild ? .end : .continuation
        ))
    }
    return result
  }
}
