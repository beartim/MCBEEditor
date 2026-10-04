# 第4轮：dimension empty 源码完成

本轮补齐已确认格式的门户及旧维度结构缓存；前两次检查点的非空特殊元数据限制已解除。源码完成不等同于原生验收完成。

清理范围：目标维度全部长度合法区块标签、digp及独占actor、明确维度的孤立actor、LimboEntities、常加载区块、旧版mVillages/villages和现代村庄（含RAID及键中维度名称）、门户data.PortalRecords中的目标DimId。原版dimension0/1/2是旧结构缓存，清空时删除目标缓存并保留或建立canonical维度根；query识别只有旧缓存的原版维度。末地清空移除指向旧实体及旧门户的DragonFight内容。

保留维度登记、维度根其它设置、玩家、其它维度、全局商人生成状态schedulerWT、计分板、地图及结构模板。扩大保留键/前缀并用于名称校验和发现，避免误当区块或用add覆盖全局数据。未知维度/格式、元数据冲突或无效NBT在WriteBatch前失败；不猜测未知形态，不宣称覆盖尚未发现的私有版本格式。

格式依据（2026-10-04阅读）来自mcbe-leveldb 1.21.0的发布源码；相关schema标注已验证。本项目没有复制其实现，仅用字段结构构造测试。链接：
- https://app.unpkg.com/mcbe-leveldb@1.21.0/files/nbtSchemas.ts ：Portals、SchedulerWT、LegacyOverworld/LegacyNether/LegacyTheEnd、TheEnd。
- https://app.unpkg.com/mcbe-leveldb@1.21.0/files/LevelUtils.ts ：LevelDB键分类及村庄维度前缀/RAID。

实际通过：CLI/Tests/source_audit.py、CLI/Tests/build_audit.py、CLI/Tests/apple_build_lifecycle.py（工具替身验证构建脚本）、git diff --check、完整源码ZIP校验、原示例存档字节比对。

Swift/C#测试增加门户跨维度过滤和设置保留、非空schedulerWT保留、带维度村庄和RAID、仅旧缓存维度发现/清空、末地战斗状态清除。Windows CLI原生测试增加执行empty后重新打开、目标零区块、其它维度/玩家/登记和level.dat保持不变。

实际尝试bash Scripts/test_dimension_query.sh、dotnet run --project Windows/MCBEEditor.Core.SelfTest -- --dimension均因缺少swiftc/dotnet退出127。新增原生测试没有执行，不声明编译通过、真实存档清理或重开通过。测试存档本轮未改写。待有工具链时运行上述命令及CLI/Windows.Tests原生套件。

后续：进入第5轮purge；整体原生验收仍是阶段8未完成项。所有旧命令任意维度支持尚在第6–7轮，未提前宣称实现。
