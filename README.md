# Desk Pond

一个 2D 像素桌面陪伴小游戏：你专注，它钓鱼；你完成计划，它长树。

## 当前功能

- 可配置专注/休息时长的番茄钟。
- 点击池塘或“甩杆”开始专注，专注结束后自动进入休息倒计时。
- 今日任务苗圃，完成任务会增加树的成长值。
- 完整代办清单窗口，适合管理更多任务。
- 自动钓鱼奖励和钓获图鉴。
- 本地保存每日任务、番茄数、鱼类收藏、树成长和窗口置顶设置。

## 运行方式

使用 Godot 4.6 或更新版本打开本项目，运行 `scenes/Main.tscn`。

本机 Steam 版 Godot 可执行文件示例：

```powershell
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --path 'C:\工位池塘'
```

## 验证命令

```powershell
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path 'C:\工位池塘' --quit-after 2
```

## 操作说明

- 点击池塘水面，或按“甩杆”，开始一次专注。
- 在左侧调整专注和休息分钟数，开始后设置会锁定。
- 在右侧写下今日任务，勾选完成后小树成长。
- 点“展开”打开完整代办清单。
- 点“图鉴”查看钓获收藏。
- 点“?”查看玩法说明。
