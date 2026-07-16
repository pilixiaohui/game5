# 异种起源：无尽洪流

基于 Godot 4.7 的 Windows 桌面首小时可玩切片。第一版实现同一存档中的虫巢生产、虫群形成、持续节点战斗、残骸/样本回流、突变选择、区域出口与飞升只读预览。

## 运行

```bash
godot4 --path .
```

最低有效窗口为 `1280 x 720`，参考视口为 `1600 x 900`。主要操作使用鼠标；`Ctrl+S` 手动保存，`F11` 切换全屏。

## 自动测试

```bash
./scripts/verify_fresh_source_lifecycle.sh
./scripts/verify.sh
godot4 --headless --path . -s res://tests/test_runner.gd
./scripts/verify_screenshots.sh
```

`verify_fresh_source_lifecycle.sh` 是无 `.godot` 源码的正式窄门：它在精确 clean clone 中只执行一次独立 40 秒 cold import，再分别执行 post-import isolation（180 秒）和 acceptance lifecycle（内部 80 秒）。直接运行 `verify_isolation.sh` 或 `verify_acceptance_regressions.sh` 只验证已完成 editor import 的工作树；前置 import 不完整时会明确非零退出，不会按需生成部分缓存。

游戏存档位于 `user://saves/slot_01.json`。正式飞升、第二地区实装、第二虫巢和多战场属于明确锁定内容。
