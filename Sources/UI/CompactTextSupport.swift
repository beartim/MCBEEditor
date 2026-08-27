import UIKit

/// Keeps dense editor labels readable on narrow iPhone layouts by preferring
/// font shrinking over an early ellipsis. Multi-line table labels use a small iPhone-only cap.
extension UILabel {
  func mcbe_enableCompactSingleLineText(minimumScaleFactor: CGFloat = 0.60) {
    guard numberOfLines == 1 else { return }
    adjustsFontSizeToFitWidth = true
    self.minimumScaleFactor = min(self.minimumScaleFactor == 0 ? 1 : self.minimumScaleFactor,
                                  minimumScaleFactor)
    baselineAdjustment = .alignCenters
  }
}

extension UIButton {
  func mcbe_enableCompactTitle(minimumScaleFactor: CGFloat = 0.60) {
    guard let titleLabel = titleLabel else { return }
    titleLabel.numberOfLines = 1
    titleLabel.adjustsFontSizeToFitWidth = true
    titleLabel.minimumScaleFactor = minimumScaleFactor
    titleLabel.baselineAdjustment = .alignCenters
  }
}

extension UITableViewCell {
  /// Built-in UITableViewCell labels often get squeezed by disclosure icons,
  /// badges and iPhone safe areas. Shrink them before truncating.
  func mcbe_enableCompactText() {
    guard UIDevice.current.userInterfaceIdiom == .phone else { return }
    if let label = textLabel {
      if label.numberOfLines == 1 {
        label.mcbe_enableCompactSingleLineText(minimumScaleFactor: 0.58)
      } else if label.font.pointSize > 15 {
        // adjustsFontSizeToFitWidth only works reliably for one-line labels.
        // Use an idempotent iPhone cap for multi-line built-in cell labels.
        label.font = label.font.withSize(15)
        label.lineBreakMode = .byWordWrapping
      }
    }
    if let label = detailTextLabel {
      if label.numberOfLines == 1 {
        label.mcbe_enableCompactSingleLineText(minimumScaleFactor: 0.52)
      } else if label.font.pointSize > 13 {
        label.font = label.font.withSize(13)
        label.lineBreakMode = .byWordWrapping
      }
    }
  }
}
