MCBEEditor 构建修复记录 · logs_93351559292 · 2026-09-10

- 修复 `Scripts/test_block_colors_project_audit.sh` 的过期源码断言。
- X/Z 剖面配色现已通过 `BedrockBlockMapColorInput(state:)` 统一提取现代状态颜色变体及旧格式 `legacyID` / `legacyData`；旧测试仍硬编码查找已删除的 `legacyID: primary?.legacyID`，导致实际功能正常时 CI 仍返回 exit code 1。
- 审计现在验证当前实现路径：`BedrockBlockMapColorInput(state: value.state)`、`input.legacyID`、`input.legacyData`、`input.variantIdentifier`，继续保证旧方块 metadata 与现代 block states 都会传入共用颜色目录。
- `test_block_colors_project_audit.sh`、`test_block_colors_full_audit.sh`、`test_export_options_texture_overrides.sh`、`test_shared_command_file.sh`、`test_source_audit.sh` 均已单独通过。
- 软件版本保持 1.0.0（100），未改变功能行为或存档读写格式。
