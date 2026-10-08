# Desk Pond

[![最新版本](https://img.shields.io/badge/%E6%9C%80%E6%96%B0%E7%89%88%E6%9C%AC-v0.7.0-c9824a)](https://github.com/Mr-Salticidae/desk-pond/releases/latest)

一个 2D 像素桌面陪伴小游戏：你专注，它钓鱼；你完成计划，它长树；攒下的贝壳，拿去搭一只属于你的生态缸。

## 下载

前往 [Releases 页面](https://github.com/Mr-Salticidae/desk-pond/releases/latest) 下载最新的 **DeskPond-v*.exe**（文件名带版本号），双击即可运行，无需安装（单文件已内置全部资源）。

### 其他平台

- **macOS**：下载 **DeskPond-macOS-v*.zip**，双击解压后打开。因未做 Apple 公证，首次打开需在「系统设置 → 隐私与安全性」底部点「仍要打开」放行一次（Universal 双架构，Apple Silicon / Intel 通用）。
- **手机 / 网页版**：Web 导出（竖屏布局、全面屏适配：在 B站 App 内自动进入沉浸模式并避让刘海 / 手势条），通过 B站 toy 托管发布：[点这里直接玩](https://www.bilibili.com/toy/6BterUHrdJEq8SiW/index.html)。电脑版“复制链接”分享出去的也是这个页面，朋友点开就能逛你的缸。

## 从源码导出

- Windows：`godot --headless --path . --export-release "Windows Desktop" build/DeskPond.exe`
- Web（手机版，线程禁用保 webview 兼容）：`godot --headless --path . --export-release Web build/web/index.html`
  - 传 B站 toy 需再跑 `make_toy_package.ps1`：toy 托管会吞 `.pck` 文件，脚本将其改名 `.data` 并给 index.html 打 mainPack 补丁后重新打 zip
- macOS（Windows 上交叉导出，自动 ad-hoc 签名）：`godot --headless --path . --export-release macOS build/DeskPond-macOS.zip`

导出目录需先手动创建；Web 与 macOS 的适配差异细节见本地 `promo/` 目录下的发布说明（营销物料不入库）。

## 当前功能

- 可配置专注/休息时长的番茄钟，支持倒计时 / 正计时（正计时从 0 往上数，自己收竿，满 1 分钟算一次专注）。
- 点击池塘或“甩杆”开始专注，专注结束后自动进入休息倒计时。
- 今日任务苗圃，完成任务会增加树的成长值。
- 完整代办清单窗口，适合管理更多任务。
- 自动钓鱼奖励，钓到的鱼住进水族馆；森林记录累计完成的任务。
- **生态缸**：专注和完成任务得到贝壳，在商店买水草、造景、装饰、设备和小生物，拖进缸里自由布置（左右摆位置，上下调前后）。
- 轻量生态模拟：氧气 / 水质要跟得上鱼的数量，美观来自摆件与主题套组，合成生态星级；星级解锁新物件和扩缸。失衡只会让评分打折、鱼浮头、水发浑，永远不会死鱼。
- 访客：布置出特定的缸（海螺壳、茂密水草、沉木 + 苔藓球……），专注完成时寄居蟹、小海马、六角恐龙等会游进来。
- 鱼的互动：点水面喂鱼、点鱼看名字和等级；同种鱼钓得越多等级越高；缸里每天冒出珍珠泡泡，点一下收集贝壳。
- 全屏：收起下方控制台，让场景占满窗口 / 手机整屏。
- 桌面版窗口可拖动右边 / 下边 / 右下角调整大小：内容等比放大，比例不同时多出来的空间留给场景；下次打开记住大小。
- **分享**：一键生成生态缸卡片图（缸名、星级、鱼和访客，B站 App 内附二维码），分享 / 存相册 / 复制链接，不用再手动截图。朋友点开链接直接逛你的缸、帮你喂鱼，不需要账号或服务器；电脑版也能粘贴分享码去朋友家看看。
- 成长档案，只增不减；应用开着跨过午夜也会自动换天（重置今日计数、结转未完成的任务）。
- **每日记录**：每天记一行（专注分钟、番茄数、完成的任务、贝壳、钓到的鱼），档案里看最近 14 天的小柱图和本周合计。不做连胜，空白的日子不标红。
- **角落小窗**（桌面版）：顶栏小窗图标把池塘缩成屏幕角落的一条（300×84，自动置顶），计时和甩杆都在上面；小窗里专注完成冒一个气泡，展开时补看完整奖励。
- **到点提醒**：专注结束、休息结束时窗口不在前台，任务栏按钮会闪一下（macOS 是 Dock 图标跳动）；休息结束也会轻轻响一声。
- **昼夜**：池塘、森林和水族馆跟着本地时间换天色（清晨 / 白天 / 黄昏 / 夜晚），夜里有星星、亮着的显示器和萤火虫。只改画面，不锁内容；玩法说明底部可以改成「一直白天」。
- **新版本提示**（桌面版）：启动时从 tiaozhuxiansheng.com 读一个版本号文件，有新版就在「?」上亮个小点。不上传任何数据、不自动下载，可在玩法说明底部关掉。
- 轻量环境水声与事件音效，顶栏「声 / 静」一键开关。
- 本地保存每日任务、番茄数、鱼类收藏、树成长、每日记录、计时方式、声音、窗口置顶、窗口大小、小窗位置与昼夜设置。

## 运行方式

使用 Godot 4.6 或更新版本打开本项目，运行 `scenes/Main.tscn`。

本机 Steam 版 Godot 可执行文件示例：

```powershell
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --path 'C:\工位池塘'
```

## 验证命令

```powershell
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path 'C:\工位池塘' --quit-after 2
# 生态缸 / 分享码逻辑测试（全部通过时退出码 0）
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path 'C:\工位池塘' --script tests/test_eco.gd
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path 'C:\工位池塘' --script tests/test_share.gd
# 番茄钟（倒计时 / 正计时）与桌面布局（各房间、各窗口大小下控制台都不超出窗口）测试
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path 'C:\工位池塘' --script tests/test_timer.gd
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path 'C:\工位池塘' --script tests/test_layout.gd
# v0.7：每日记录、角落小窗与到点提醒、昼夜、新版本提示（不联网）
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path 'C:\工位池塘' --script tests/test_daily.gd
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path 'C:\工位池塘' --script tests/test_mini.gd
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path 'C:\工位池塘' --script tests/test_day_cycle.gd
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path 'C:\工位池塘' --script tests/test_update.gd
# 苹果式控件：步进器、分段控件（替代 SpinBox 和小开关）
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path 'C:\工位池塘' --script tests/test_controls.gd
# 网页 / 手机版像素字体的缺字检查（字体里没有的字会画成方框）
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path 'C:\工位池塘' --script tests/test_glyphs.gd
# 固定在某个钟点看昼夜效果（例：晚上九点半）
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --path 'C:\工位池塘' -- --hour=21.5
# 在桌面上预览手机布局（390×844，模拟刘海与手势条）
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --path 'C:\工位池塘' -- --web-layout --web-size=390x844 --safe-area=44,0,34,0
```

## 操作说明

- 点击池塘水面，或按“甩杆”，开始一次专注。
- 在左侧调整专注和休息分钟数，开始后设置会锁定。
- 钓竿右上角切换「倒计时 / 正计时」；正计时专注中主按钮变成「收竿」，点它结算（不满 1 分钟算空竿）。
- 桌面版拖窗口的右边、下边或右下角手柄调整大小。
- 顶栏小窗图标进入角落小窗；小窗整条都能拖动，点「展开」或双击回到完整窗口。
- 在右侧写下今日任务，勾选完成后小树成长。
- 点“展开”打开完整代办清单。
- 顶栏的贝壳数可直接打开水族商店。
- 水族馆右上角：“鱼缸”看缸、“图鉴”看鱼和访客、“布置”摆放、“全屏”收起控制台。
- 布置时：底部库存条点一下放进缸，拖动摆放，工具条“翻转 / 收回”。
- 点缸左上角的星级查看生态报告（氧气、水质、美观、生机与建议）。
- 水族馆右上角“分享”：给缸起名、生成卡片，分享 / 保存图片 / 复制链接；下方粘贴朋友的分享码或链接可以去他家看看。
  - 电脑版分享默认给「分享码 + 说明」；把 `scripts/eco_share.gd` 里的 `SHARE_WEB_URL` 填成 B站 Toy 页面地址后，会改为可点开的链接。
- 点“?”查看玩法说明；底部有「昼夜跟随本地时间」「启动时检查新版本」两个开关。
- 设计思路见 `docs/设计_生态缸.md`、`docs/设计_v0.7_小窗与昼夜.md`。
