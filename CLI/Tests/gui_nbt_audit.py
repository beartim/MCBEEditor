#!/usr/bin/env python3
"""GUI/store source contracts; these do not replace native or UI tests."""
from pathlib import Path
r=Path(__file__).resolve().parents[2]
s=(r/'Sources/Entity/BedrockWorldObjectNBTStore.swift').read_text()
c=(r/'Windows/MCBEEditor.Core/Entity/BedrockWorldObjectNbtStore.cs').read_text()
u=(r/'Sources/UI/WorldObjectNBTEditorViewController.swift').read_text()
w=(r/'Windows/MCBEEditor.Desktop/NbtEditorWindow.cs').read_text()
assert 'UniqueID 已变化或不唯一' in s and 'UniqueID 已变化或不唯一' in c, 'stale UID must not fall back to coordinates'
assert 'object = try store.refreshedObject' in u, 'iOS repeated saves need refreshed identity'
assert 'HasPendingValue' in w and '_dirty || HasPendingValue' in w, 'unapplied text must guard close'
assert 'MessageBoxButton.YesNoCancel' in w and 'SaveAndCloseAsync' in w, 'close must allow save/discard/cancel'
assert 'if (_saving)' in w and 'editorContent.IsEnabled = false' in w, 'pending save must block edits and close'
assert 'navigationController?.isModalInPresentation = hasUnsavedChanges' in (r/'Sources/UI/UnsavedNBTExitGuard.swift').read_text(), 'modal swipe must not discard edits'
guard_source = (r/'Sources/UI/UnsavedNBTExitGuard.swift').read_text()
exit_body = guard_source.split('private func exitEditor()', 1)[1]
assert 'controller.isModalInPresentation = originalModalInPresentation' in exit_body
assert 'navigationController?.isModalInPresentation = originalNavigationModalInPresentation' in exit_body
print('PASS: GUI NBT identity/save source contracts (not native behavior)')

# A saved block entity must rebind the open editor before another save.
assert "currentObject = store.RefreshedObject(item, edited);" in (Path(__file__).resolve().parents[2] / "Windows/MCBEEditor.Desktop/MainWindow.xaml.cs").read_text()
