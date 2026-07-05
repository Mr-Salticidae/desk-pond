# Desk Pond

[![最新版本](https://img.shields.io/badge/%E6%9C%80%E6%96%B0%E7%89%88%E6%9C%AC-v0.5.0-c9824a)](https://github.com/Mr-Salticidae/desk-pond/releases/latest)

一个 2D 像素桌面陪伴小游戏：你专注，它钓鱼；你完成计划，它长树。

## 下载

前往 [Releases 页面](https://github.com/Mr-Salticidae/desk-pond/releases/latest) 下载最新的 **DeskPond-v*.exe**（文件名带版本号），双击即可运行，无需安装（单文件已内置全部资源）。

### 其他平台

- **macOS**：下载 **DeskPond-macOS-v*.zip**，双击解压后打开。因未做 Apple 公证，首次打开需在「系统设置 → 隐私与安全性」底部点「仍要打开」放行一次（Universal 双架构，Apple Silicon / Intel 通用）。
- **手机 / 网页版**：Web 导出（竖屏布局适配），通过 B站 toy 托管发布，入口见发布动态。

## 从源码导出

- Windows：`godot --headless --path . --export-release "Windows Desktop" build/DeskPond.exe`
- Web（手机版，线程禁用保 webview 兼容）：`godot --headless --path . --export-release Web build/web/index.html`
- macOS（Windows 上交叉导出，自动 ad-hoc 签名）：`godot --headless --path . --export-release macOS build/DeskPond-macOS.zip`

导出目录需先手动创建；Web 与 macOS 的适配差异细节见本地 `promo/` 目录下的发布说明（营销物料不入库）。

## 当前功能

- 可配置专注/休息时长的番茄钟。
- 点击池塘或“甩杆”开始专注，专注结束后自动进入休息倒计时。
- 今日任务苗圃，完成任务会增加树的成长值。
- 完整代办清单窗口，适合管理更多任务。
- 自动钓鱼奖励，钓到的鱼在水族馆里游动；森林记录累计完成的任务。
- 成长档案与水缸布置，按进度解锁、只增不减。
- 轻量环境水声与事件音效，顶栏「声 / 静」一键开关。
- 本地保存每日任务、番茄数、鱼类收藏、树成长、声音与窗口置顶设置。

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
