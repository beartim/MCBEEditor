# Photo export XcodeGen Info.plist fix

## Root cause

The previous source package contained `NSPhotoLibraryAddUsageDescription` and
`NSPhotoLibraryUsageDescription` directly in `Resources/Info.plist`, but the
GitHub Actions workflow runs `Scripts/bootstrap.sh` before the portable tests.
That script invokes XcodeGen, and the `info.properties` section of `project.yml`
is the authoritative source for the generated plist. Because the two privacy
keys were absent there, XcodeGen regenerated `Resources/Info.plist` without
them. The following regression test then correctly failed.

## Fix

- Added both photo-library privacy descriptions to `MCBEEditor.info.properties`
  in `project.yml`.
- Added `Photos.framework` explicitly to the app target dependencies.
- Extended `test_photo_export_tabs_keyboard.sh` to verify both the generated
  plist and the XcodeGen source configuration.
- Added a post-XcodeGen check in `Scripts/bootstrap.sh` so missing privacy keys
  fail immediately during project generation instead of later in the test/build.
- Kept the iOS 13 legacy authorization path and the iOS 14+ add-only path.

This fixes the configuration at its source rather than patching a generated
file that XcodeGen can overwrite.
