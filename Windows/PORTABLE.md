# Windows 绿色单文件发布

运行 `Windows\build.cmd` 后，最终可分发文件为：

```text
Windows\dist\MCBEEditor.exe
```

`dist` 在构建完成时只保留这一份 EXE。该 EXE 是原生便携启动器，内部嵌入 .NET 10 x64 自包含 WPF 单文件载荷和应用所需的原生 LevelDB 桥。

## 运行目录

第一次运行会在 `MCBEEditor.exe` 同级创建：

```text
Textures\
  ReadMe.txt
Commands\
  ReadMe.txt
  Command.txt   # 仅用户自行创建时存在
Cache\          # 仅运行期间存在
```

`Textures`、`Commands` 为用户持久目录；MCBEEditor 不再创建或读取用户 Documents 下的同名目录。

`Cache` 包含运行时临时载荷、.NET bundle 解包、世界工作副本和临时导出文件。启动器在启动前清理异常退出残留，并在主程序完全退出后再次递归删除整个 `Cache`。

## 世界编辑原则

原始世界文件夹、`.mcworld` 或 ZIP 只作为输入。打开后先复制/解压到 `Cache\Worlds`，所有世界修改只针对临时工作副本。

主页“导出 .mcworld”是世界编辑结果唯一持久化出口。程序拒绝：

- 覆盖原始 `.mcworld`/ZIP；
- 把导出文件写到原始世界文件夹内部；
- 把导出文件写到 `Cache`；
- 使用 `.mcworld` 以外的世界导出扩展名。

导出的 `.mcworld` 会排除 MCBEEditor 私有设置/元数据和 LevelDB `db/LOCK`。
