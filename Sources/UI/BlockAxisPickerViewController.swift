import UIKit

final class BlockAxisPickerViewController: UIViewController, UIPickerViewDataSource, UIPickerViewDelegate {
  private let result: BedrockBlockAxisLineResult
  private let onSelect: (BedrockBlockRecord) -> Void
  private let picker = UIPickerView()
  private let detailLabel = UILabel()
  private var selectedRow = 0

  init(
    result: BedrockBlockAxisLineResult,
    initialCoordinate: Int64?,
    onSelect: @escaping (BedrockBlockRecord) -> Void
  ) {
    self.result = result
    self.onSelect = onSelect
    // `blockAxisLine` is ordered from the largest X/Z coordinate downward.
    // Prefer the largest-coordinate non-air block so a tap immediately lands
    // on the foremost visible projected block. Fall back to the tapped plane
    // coordinate only when the entire selectable axis line is air/missing.
    if let index = result.blocks.firstIndex(where: { !$0.primaryState.isAir }) {
      selectedRow = index
    } else if let initialCoordinate = initialCoordinate,
      let index = result.blocks.firstIndex(where: {
        result.axis == .x ? $0.x == initialCoordinate : $0.z == initialCoordinate
      })
    {
      selectedRow = index
    }
    super.init(nibName: nil, bundle: nil)
    title = "选择\(result.axis.displayName)轴方块"
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: "选择", style: .done, target: self, action: #selector(done))

    picker.dataSource = self
    picker.delegate = self
    picker.translatesAutoresizingMaskIntoConstraints = false
    detailLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    detailLabel.textColor = .secondaryLabel
    detailLabel.numberOfLines = 5
    detailLabel.textAlignment = .center
    detailLabel.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(picker)
    view.addSubview(detailLabel)
    NSLayoutConstraint.activate([
      picker.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
      picker.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
      picker.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
      picker.heightAnchor.constraint(equalToConstant: 260),
      detailLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      detailLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
      detailLabel.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 8),
      detailLabel.bottomAnchor.constraint(
        lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
    ])
    if !result.blocks.isEmpty {
      picker.selectRow(selectedRow, inComponent: 0, animated: false)
      updateDetail(row: selectedRow)
    }
    preferredContentSize = CGSize(width: 460, height: 400)
  }

  func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
  func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
    result.blocks.count
  }

  func pickerView(
    _ pickerView: UIPickerView,
    attributedTitleForRow row: Int,
    forComponent component: Int
  ) -> NSAttributedString? {
    guard result.blocks.indices.contains(row) else { return nil }
    let block = result.blocks[row]
    let coordinate = result.axis == .x ? block.x : block.z
    let generated = block.isGenerated ? "" : "  [未生成]"
    let text = "\(result.axis.displayName)=\(coordinate)   \(block.primaryState.identifierDescription)\(generated)"
    return NSAttributedString(string: text, attributes: [
      .font: UIFont.monospacedSystemFont(
        ofSize: 14, weight: block.primaryState.isAir ? .regular : .semibold),
      .foregroundColor: block.primaryState.isAir ? UIColor.secondaryLabel : UIColor.label,
    ])
  }

  func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
    selectedRow = row
    updateDetail(row: row)
  }

  private func updateDetail(row: Int) {
    guard result.blocks.indices.contains(row) else { return }
    let block = result.blocks[row]
    var text = "\(block.coordinateDescription)\n\(block.primaryState.identifierDescription)"
    let properties = block.primaryState.statePropertiesDescription
    if properties != "无方块状态" {
      text += "\n\(properties.replacingOccurrences(of: "\n", with: "；"))"
    }
    if !result.diagnostics.isEmpty {
      text += "\n解析提示：\(result.diagnostics.count) 条"
    }
    detailLabel.text = text
  }

  @objc private func cancel() { dismiss(animated: true) }

  @objc private func done() {
    guard result.blocks.indices.contains(selectedRow) else { return }
    let block = result.blocks[selectedRow]
    dismiss(animated: true) { [onSelect] in onSelect(block) }
  }
}
