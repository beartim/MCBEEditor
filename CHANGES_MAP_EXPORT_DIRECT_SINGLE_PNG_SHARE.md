# Map export: direct single-PNG share

- Tapping the map export button now opens the system share sheet directly.
- Removed the intermediate action sheet containing “保存到相册” and “分享／存储…”.
- The share sheet now receives only the exported `.png` file URL. Previously it received both the `UIImage` and the URL for that same file, which made iOS expose two identical image items.
- Removed the no-longer-used direct PhotoKit save path and `Photos.framework` dependency. The photo-library privacy descriptions remain because the system share sheet’s “Save Image/存入相册” activity still writes to Photos on behalf of the app.
- Kept the exported filename and PNG encoding unchanged.
