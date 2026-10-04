Dimension.txt 演示无 namespace 和有 namespace 的维度，以及同批新增后按名称执行其它命令。文件包含写入、清空和删除，应对复制品运行并指定 --output。名称 bear/wzn:demo 和 ID 1003/1004 必须尚未占用；先用 dimension query 查看。
RestoreVanilla.txt 用于重建均缺失的下界和末地；若已有其中一个，应删除对应 add 行。已有的名称或 ID 会被整批预检拒绝。
--check/--check-file 无世界上下文，只检查名称 token 和语法；实际执行在工作副本上绑定当前世界并再次预检。任一预检失败均不执行命令。运行时的格式损坏、目标不存在等错误仍可能发生；CLI 继续后续命令，原位模式只有全部成功才提交。
fillbiome 接受自定义维度，但要求选区已存在可修改的生物群系记录。新建维度为空；本生命周期示例不对新维度运行 fillbiome。
