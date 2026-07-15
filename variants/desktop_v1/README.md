# 异种起源：无尽洪流

基于 Godot 4.7 的 Windows 桌面首小时可玩切片。第一版实现同一存档中的虫巢生产、虫群形成、持续节点战斗、残骸/样本回流、突变选择、区域出口与飞升只读预览。

## 运行

```bash
godot4 --path .
```

最低有效窗口为 `1280 x 720`，参考视口为 `1600 x 900`。主要操作使用鼠标；`Ctrl+S` 手动保存，`F11` 切换全屏。

## 自动测试

```bash
godot4 --headless --path . -s res://tests/test_runner.gd
godot4 --headless --path . -s res://tests/screenshot_runner.gd
```

游戏存档位于 `user://saves/slot_01.json`。正式飞升、第二地区实装、第二虫巢和多战场属于明确锁定内容。
