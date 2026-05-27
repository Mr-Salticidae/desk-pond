# Desk Pond

一个 2D 像素桌面陪伴小游戏：你工作，它钓鱼；你完成计划，它种下一棵树。

## 功能

- 番茄钟
- 今日计划
- 自动钓鱼奖励
- 树成长
- 本地保存

## 运行方式

使用 Godot 4.x 打开本项目，运行 `scenes/Main.tscn`。

当前命令行环境没有检测到 `godot` 可执行文件；如果你的 Godot 没有加入 PATH，直接用 Godot 编辑器打开 `C:\工位池塘` 即可。

## 调试

`scripts/pomodoro_timer.gd` 中默认开启：

```gdscript
const DEBUG_FAST_TIMER = true
```

开启时专注倒计时为 10 秒，便于快速测试钓鱼奖励闭环。关闭后会使用存档设置中的 25 分钟专注和 5 分钟休息。

## 当前版本

MVP 原型版。
