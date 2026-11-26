# Westie Desk Pet 🐶🐱🎾

一款原生轻量化 **macOS & Windows 跨平台桌面陪伴宠物（西高地小狗 / 金渐层小猫双角色切换）+ 2.5D 网球对打** 小应用（macOS：Swift 6 + AppKit + SpriteKit；Windows：.NET 8 + WPF + Win32 DWM，共享同一套 82 张像素精灵资产，无需管理员/辅助功能/录屏权限）。

平时它是一只安静探头在屏幕右侧边的像素风小狗或金渐层小猫，不挡窗口正文；当你专心停留在某个窗口一段时间后，它会悄悄从顶栏后方探头张望、翻身跳着走或跳一段魔性「⚡ 闪身步」，最后打个哈欠趴下睡觉；想放松一局时，随时展开半透明桌面网球场，用 **`WASD` + 鼠标** 来一场 5 分制网球对决！

---

## ✨ 核心特性

### 1. 桌面陪伴模式（v0.5 双宠物角色 · 窗后潜行 · 闪身步 · 零侵入）
- **双宠物 100% 全套像素资产切换（🐶 西高地小狗 / 🐱 金渐层小猫）**：
  - 完整复刻两只宠物的全套透明像素帧（共 82 张精灵图）：右侧探头挥爪、大头趴窗、4 帧真实四足小跑、3 帧欢快跳走、原地转头东张西望、爬顶、打哈欠、犯困半眯、团子睡觉、拎后颈、5 帧直立「闪身步」、2 帧吃零食咀嚼、网球对打全套动作，顶部菜单栏图标与网球文案实时联动切换。
- **默认常驻「屏幕右侧边」+ 定时爬顶叙事**：
  - 默认安静驻留在**屏幕最右侧边**（绝不贴在激活窗口右缘挡滚动条），紧贴真实可见狗头/猫头宽度触发悬停挥爪；也可在偏好设置中切换「优先窗口正上方」或「跟随窗口右侧边」。
  - 停留满设定时间（最低支持 `3 秒` 方便测试，默认 `1 分钟`）且未打字时，宠物自动悄悄缩回屏幕右缘，再从当前激活窗口的标题栏后方**先露小爪探头左右张望 3 秒**、翻身上顶上演完整故事。
- **双套爬顶动态特效可选**：
  - **🐾 悠闲巡逻**：镜像翻身朝左 → 3 帧真实欢快跳着向左走 → 身体不动只转头东张西望（右→左→右）→ 4 帧四足小跑向右走 → 面对镜头微笑坐下轻摆头 → 安静等 2.6 秒 → 打大哈欠 → 睁眼趴下 → 犯困半眯 → 闭眼睡着。
  - **⚡ 闪身步**：还原 5 拍直立双脚舞步（**起势 → 往右闪 → 停 → 准备 → 再往左闪 → 停**），连跳 2 轮后微笑坐下、打哈欠睡觉；也支持 **🎲 随机轮换** 与右键一键预览。
- **投喂专属零食 + 咀嚼动效**：
  - 西高地投喂 `🦴 骨头饼干`、金渐层投喂 `🐟 小鱼干`：零食弹跳落地 → 小跑冲过去 → 抱住零食 2 帧张嘴/眯眼咀嚼（伴随像素碎屑飞溅与满足冒泡）。
- **统一克制的鼠标交互 + 可视化偏好设置弹窗**：
  - **窗顶悬停绝不乱切图、不吵醒睡着的小宠**；轻点（< 4pt）在勾选的姿态（`😊 微笑歪头坐` / `🐾 安静趴卧` / `🐶 大头趴窗盯镜头` / `💤 团成团子睡觉`）间平滑循环；拖拽（≥ 4pt）带二阶阻尼弹簧钟摆惯性拎起。
  - 支持 **60% ~ 160% 宠物大小实时缩放**、换窗驻留防抖（含叠窗提前藏起与全屏原地平滑下缩防瞬移）、高速划过害羞缩头、打字免打扰与会议免打扰。

### 2. 2.5D 桌面网球模式（`WASD` + 鼠标对打 · 四档球速调节）
- **GBA《马里奥网球》风格半透明球场**：直接在桌面中央展开，支持完整三维 `(x, y, z)` 重力、球网高度判定、旋转空气动力与单打边线/二跳得分规则；对手立绘、发球/得分横幅与难度名称随当前宠物自动切换（`休闲小狗 / 网球狗王` ↔ `休闲小猫 / 网球猫王`）。
- **四档球速可调（默认慢速轻松上手）**：内置 **`🐢 慢速 (默认)` / `🎾 适中` / `⚡️ 标准` / `🔥 快速`** 四档球速并自动记忆，可通过球场顶部按钮、快捷键 `[-]` / `[+]`（或 `[` / `]`）或右键菜单随时切换。
- **操作指南（兼容中文输入法，基于硬件键码）**：
  | 操作 | 效果 |
  | :--- | :--- |
  | **`W / A / S / D`**（或方向键） | 控制底线球员前后左右跑位 |
  | **双击方向键 / `Space`** | 飞身冲刺救大角度球 |
  | **鼠标移动** | 移动对面半场的落点准星 |
  | **鼠标左键点按** | 快速平击抽球 / 发球 |
  | **鼠标左键按住蓄力松开** | 强力上旋抽球（过网急坠、落地加速） |
  | **鼠标右键点击** | 瞄近网为 **切削放小球（Drop Shot）**；瞄底线为 **高吊球（Lob）** |
  | **`-` / `=`（或 `[` / `]` / 顶部球速按钮）** | 实时调慢 / 调快网球速度 |
  | **`R` / 左键（赛末）** | 重新开球再来一局 |
  | **`ESC` / 右上角按钮 / `⌘⇧T`** | 立即收起球场，宠物回到桌面陪伴位 |

---

## 🚀 构建与运行

### macOS（Swift 6 + AppKit + SpriteKit）

环境要求：**macOS 14.0+**，安装 Xcode 或 Xcode Command Line Tools（Swift 6.0+）。

```bash
# 1. 运行内置 42 项物理、动画、AI 与双宠物资产自检
swift run WestieDeskPet --self-test

# 2. 打包独立 macOS 应用 (输出到 dist/WestieDeskPet.app)
./scripts/build_app.sh

# 3. 启动桌面伙伴！（启动后常驻顶部菜单栏，不占 Dock 图标）
open dist/WestieDeskPet.app
```

也可以直接通过命令行参数直接进入网球模式调试：

```bash
swift run WestieDeskPet --tennis
```

### Windows 10 / 11（.NET 8 + WPF + Win32 DWM）

Windows 版位于 `windows/` 目录（`WestieDeskPet.Core` + `WestieDeskPet.Windows` + `WestieDeskPet.Tests`），直接复用仓库内 82 张共享 PNG 精灵（零资产冗余），通过 `DwmGetWindowAttribute(DWMWA_EXTENDED_FRAME_BOUNDS)` 精准贴齐窗口可见边缘、`WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW` 丝滑穿透不占任务栏/Alt+Tab，并提供系统托盘图标与原生偏好设置弹窗：

```powershell
# 在 Windows 上运行测试并打包单文件便携版（含 .NET 运行时，解压即用）
.\scripts\build_windows.ps1 -Runtime win-x64 -SelfContained

# 启动（支持 --tennis 直接进入网球模式）
.\dist\windows-win-x64\WestieDeskPet.exe
```

也可以在 **macOS 上直接交叉编译** Windows 可执行文件：

```bash
# 运行核心引擎 xUnit 单元测试并交叉编译出 dist/windows-win-x64/WestieDeskPet.exe
./scripts/build_windows_from_mac.sh win-x64 false

# 如需打不依赖 .NET 运行时的独立便携包（带 -SelfContained）
./scripts/build_windows_from_mac.sh win-x64 true
```

同时已配置 GitHub Actions（`.github/workflows/windows-build.yml`），推送分支即可在 `windows-latest` 自动跑测试并产出 `WestieDeskPet-Windows-x64.zip` 下载包。

---

## 🎨 AI 像素美术资产管线（Azure GPT-Image-2.5）

全部 82 张透明背景像素精灵（西高地 43 张含共用道具 + 金渐层 39 张）均由 `scripts/generate_*.py` 与 `scripts/process_sprites.py` 通过多参考图锁形自动生成与规范化切图：

```bash
export AZURE_OPENAI_ENDPOINT="https://<your-resource>.openai.azure.com"
export AZURE_OPENAI_API_KEY="<your-api-key>"

uv run --with pillow --with numpy python scripts/generate_assets.py
uv run --with pillow --with numpy python scripts/process_sprites.py
```
