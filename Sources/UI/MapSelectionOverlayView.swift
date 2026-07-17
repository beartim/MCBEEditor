import UIKit

enum MapSelectionEdge: CaseIterable {
    case left, right, top, bottom
}

private final class MapSelectionEdgeHandleView: UIView {
    private let visibleBar = UIView()
    private let edge: MapSelectionEdge

    init(edge: MapSelectionEdge) {
        self.edge = edge
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = true
        visibleBar.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.92)
        visibleBar.layer.cornerRadius = 5
        visibleBar.layer.borderColor = UIColor.white.cgColor
        visibleBar.layer.borderWidth = 1.5
        visibleBar.isUserInteractionEnabled = false
        addSubview(visibleBar)
        accessibilityLabel = edge.accessibilityLabel
        accessibilityTraits = .adjustable
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        switch edge {
        case .left, .right:
            visibleBar.frame = CGRect(x: (bounds.width - 14) / 2, y: 7, width: 14, height: max(20, bounds.height - 14))
        case .top, .bottom:
            visibleBar.frame = CGRect(x: 7, y: (bounds.height - 14) / 2, width: max(20, bounds.width - 14), height: 14)
        }
    }
}

final class MapSelectionOverlayView: UIView, UITextFieldDelegate {
    private let fillLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let panel = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let x0Field = UITextField()
    private let z0Field = UITextField()
    private let x1Field = UITextField()
    private let z1Field = UITextField()
    private let actionButton = UIButton(type: .system)
    private var handles = [MapSelectionEdge: UIView]()
    private var passesBackgroundTouches = false

    private(set) var selectionRect: CGRect?
    var onEdgePan: ((MapSelectionEdge, CGPoint, UIGestureRecognizer.State) -> Void)?
    var onCoordinatesChanged: ((Int64, Int64, Int64, Int64) -> Void)?
    var onShowActions: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        backgroundColor = .clear
        clipsToBounds = true

        fillLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.16).cgColor
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = UIColor.systemBlue.cgColor
        borderLayer.lineWidth = 2
        borderLayer.lineDashPattern = [7, 4]
        for item in [fillLayer, borderLayer] {
            item.contentsScale = UIScreen.main.scale
            layer.addSublayer(item)
        }

        configurePanel()
        configureHandles()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Once a final selection exists, empty overlay space should pass touches
    /// to the underlying scroll view so the user can pan and pinch the map.
    /// The coordinate panel and enlarged edge handles remain interactive.
    func setBackgroundPassThrough(_ enabled: Bool) {
        passesBackgroundTouches = enabled
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled, self.point(inside: point, with: event) else { return nil }
        if let hit = super.hitTest(point, with: event), hit !== self {
            return hit
        }
        return passesBackgroundTouches ? nil : self
    }

    private func configurePanel() {
        panel.layer.cornerRadius = 11
        panel.clipsToBounds = true
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.isHidden = true
        addSubview(panel)

        let title = UILabel()
        title.text = "选择范围"
        title.font = .preferredFont(forTextStyle: .headline)

        for field in [x0Field, z0Field, x1Field, z1Field] {
            field.borderStyle = .roundedRect
            field.keyboardType = .numbersAndPunctuation
            field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            field.textAlignment = .center
            field.delegate = self
            field.addTarget(self, action: #selector(coordinateEditingEnded), for: .editingDidEnd)
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 68).isActive = true
        }
        x0Field.placeholder = "X0"
        z0Field.placeholder = "Z0"
        x1Field.placeholder = "X1"
        z1Field.placeholder = "Z1"

        actionButton.setTitle("操作…", for: .normal)
        actionButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        actionButton.addTarget(self, action: #selector(showActions), for: .touchUpInside)

        let row0 = coordinateRow("起点", x0Field, z0Field)
        let row1 = coordinateRow("终点", x1Field, z1Field)
        let stack = UIStackView(arrangedSubviews: [title, row0, row1, actionButton])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 8),
            panel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
            panel.widthAnchor.constraint(lessThanOrEqualToConstant: 270),
            stack.leadingAnchor.constraint(equalTo: panel.contentView.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: panel.contentView.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: panel.contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: panel.contentView.bottomAnchor, constant: -8)
        ])
    }

    private func coordinateRow(_ title: String, _ x: UITextField, _ z: UITextField) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        label.widthAnchor.constraint(equalToConstant: 30).isActive = true
        let xLabel = UILabel()
        xLabel.text = "X"
        xLabel.font = .preferredFont(forTextStyle: .caption1)
        let zLabel = UILabel()
        zLabel.text = "Z"
        zLabel.font = .preferredFont(forTextStyle: .caption1)
        let stack = UIStackView(arrangedSubviews: [label, xLabel, x, zLabel, z])
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        return stack
    }

    private func configureHandles() {
        for edge in MapSelectionEdge.allCases {
            let handle = MapSelectionEdgeHandleView(edge: edge)
            handle.isHidden = true
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleEdgePan(_:)))
            pan.minimumNumberOfTouches = 1
            pan.maximumNumberOfTouches = 1
            handle.addGestureRecognizer(pan)
            addSubview(handle)
            handles[edge] = handle
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fillLayer.frame = bounds
        borderLayer.frame = bounds
        layoutHandles()
    }

    func show(rect: CGRect, region: BedrockMapRegion? = nil) {
        let normalized = rect.standardized.intersection(bounds)
        guard !normalized.isNull, normalized.width > 0, normalized.height > 0 else {
            clear()
            return
        }
        selectionRect = normalized
        let path = UIBezierPath(rect: normalized).cgPath
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.path = path
        borderLayer.path = path
        CATransaction.commit()
        panel.isHidden = false
        handles.values.forEach { $0.isHidden = false }
        if let region = region { updateCoordinateFields(region) }
        setNeedsLayout()
    }

    func updateCoordinateFields(_ region: BedrockMapRegion) {
        guard !x0Field.isFirstResponder, !z0Field.isFirstResponder,
              !x1Field.isFirstResponder, !z1Field.isFirstResponder else { return }
        x0Field.text = String(region.minimumX)
        z0Field.text = String(region.minimumZ)
        x1Field.text = String(region.maximumX)
        z1Field.text = String(region.maximumZ)
    }

    func clear() {
        selectionRect = nil
        passesBackgroundTouches = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.path = nil
        borderLayer.path = nil
        CATransaction.commit()
        panel.isHidden = true
        handles.values.forEach { $0.isHidden = true }
    }

    func containsInteractiveControl(_ view: UIView?) -> Bool {
        guard let view = view else { return false }
        if view === panel || view.isDescendant(of: panel) { return true }
        return handles.values.contains(where: { view === $0 || view.isDescendant(of: $0) })
    }

    private func layoutHandles() {
        guard let rect = selectionRect else { return }
        // The touch targets are deliberately much larger than the visible bars.
        // This keeps thin or highly zoomed-out selections easy to adjust.
        let longSide: CGFloat = 70
        let hitThickness: CGFloat = 44
        handles[.left]?.frame = CGRect(
            x: rect.minX - hitThickness / 2,
            y: rect.midY - longSide / 2,
            width: hitThickness,
            height: longSide
        ).intersection(bounds)
        handles[.right]?.frame = CGRect(
            x: rect.maxX - hitThickness / 2,
            y: rect.midY - longSide / 2,
            width: hitThickness,
            height: longSide
        ).intersection(bounds)
        handles[.top]?.frame = CGRect(
            x: rect.midX - longSide / 2,
            y: rect.minY - hitThickness / 2,
            width: longSide,
            height: hitThickness
        ).intersection(bounds)
        handles[.bottom]?.frame = CGRect(
            x: rect.midX - longSide / 2,
            y: rect.maxY - hitThickness / 2,
            width: longSide,
            height: hitThickness
        ).intersection(bounds)
    }

    @objc private func handleEdgePan(_ recognizer: UIPanGestureRecognizer) {
        guard let handle = recognizer.view,
              let edge = handles.first(where: { $0.value === handle })?.key else { return }
        let translation = recognizer.translation(in: self)
        onEdgePan?(edge, translation, recognizer.state)
    }

    @objc private func coordinateEditingEnded() {
        guard let x0 = Int64(x0Field.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""),
              let z0 = Int64(z0Field.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""),
              let x1 = Int64(x1Field.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""),
              let z1 = Int64(z1Field.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") else { return }
        onCoordinatesChanged?(x0, z0, x1, z1)
    }

    @objc private func showActions() { onShowActions?() }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        coordinateEditingEnded()
        return true
    }
}

private extension MapSelectionEdge {
    var accessibilityLabel: String {
        switch self {
        case .left: return "拖动左边界"
        case .right: return "拖动右边界"
        case .top: return "拖动上边界"
        case .bottom: return "拖动下边界"
        }
    }
}
