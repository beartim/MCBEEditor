# NBTTreeCell UIScrollView directional-lock compile fix

- Fixed the Xcode 15.4 / iOS 17.5 SDK compile error in `NBTTreeCell.swift`.
- Replaced the obsolete Swift spelling `UIScrollView.directionalLockEnabled` with the current imported API name `UIScrollView.isDirectionalLockEnabled`.
- Preserved the NBT row horizontal-scroll behavior and directional locking.
- Added regression checks that require `isDirectionalLockEnabled` and reject the obsolete spelling.
