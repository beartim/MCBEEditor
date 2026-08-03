import UIKit

/// Replaces the navigation back affordance only while an NBT editor has
/// unsaved changes. Interactive swipe-back is disabled in that state so edits
/// cannot be discarded without the same confirmation dialog.
final class UnsavedNBTExitGuard: NSObject {
  private weak var controller: UIViewController?
  private let isDirty: () -> Bool
  private let saveChanges: () -> Bool
  private var originalLeftItem: UIBarButtonItem?
  private var originalHidesBackButton = false
  private var capturedOriginalState = false

  init(
    controller: UIViewController,
    isDirty: @escaping () -> Bool,
    saveChanges: @escaping () -> Bool
  ) {
    self.controller = controller
    self.isDirty = isDirty
    self.saveChanges = saveChanges
    super.init()
  }

  deinit {
    controller?.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
  }

  func synchronize() {
    guard let controller = controller else { return }
    if !capturedOriginalState {
      originalLeftItem = controller.navigationItem.leftBarButtonItem
      originalHidesBackButton = controller.navigationItem.hidesBackButton
      capturedOriginalState = true
    }

    if isDirty() {
      controller.navigationItem.hidesBackButton = true
      let item = UIBarButtonItem(
        image: UIImage(systemName: "chevron.backward"),
        style: .plain,
        target: self,
        action: #selector(attemptExit)
      )
      item.accessibilityLabel = "返回"
      controller.navigationItem.leftBarButtonItem = item
      controller.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
    } else {
      controller.navigationItem.leftBarButtonItem = originalLeftItem
      controller.navigationItem.hidesBackButton = originalHidesBackButton
      controller.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }
  }

  @objc private func attemptExit() {
    guard let controller = controller else { return }
    guard isDirty() else {
      exitEditor()
      return
    }

    let alert = UIAlertController(
      title: "有未保存的修改",
      message: "当前 NBT 标签已修改。请选择退出方式。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "不保存直接退出", style: .destructive) { [weak self] _ in
      self?.exitEditor()
    })
    alert.addAction(UIAlertAction(title: "保存退出", style: .default) { [weak self] _ in
      guard let self = self, self.saveChanges() else { return }
      self.exitEditor()
    })
    controller.present(alert, animated: true)
  }

  private func exitEditor() {
    guard let controller = controller else { return }
    if let navigation = controller.navigationController,
       navigation.viewControllers.first !== controller {
      navigation.popViewController(animated: true)
    } else {
      controller.dismiss(animated: true)
    }
  }
}
