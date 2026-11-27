# Westie Desk Pet 🐶🐱🐕🐈🎾

一款原生轻量化 **macOS & Windows 跨平台桌面陪伴宠物 + 2.5D 网球对打** 小应用（**macOS**：Swift 6 + AppKit + SpriteKit；**Windows 10/11**：.NET 8 + WPF + Win32 DWM，共享同一套 **274 张**像素风透明精灵素材，无需管理员/辅助功能/录屏权限）。

内置 **4 只可一键切换的像素桌面伙伴**（**🐶 西高地小狗 / 🐱 金渐层小猫 / 🐕 拉布拉多小狗 / 🐈 金吉拉小猫**）。平时安静探头在屏幕最右侧边零打扰陪伴；专心停留在某个窗口后，会悄悄爬上窗口顶栏左看右看趴窗发呆，并按设定间隔上演 **7 组独立趣味特效**（右键一级菜单也可随时单独点播）；累了还可以随时展开半透明桌面网球场，用 **`WASD` + 鼠标** 来一场 5 分制网球对决！

---

## ✨ 核心特性

### 1. 四大宠物 100% 全套像素素材一键切换（共 274 张 PNG）
- **🐶 西高地小狗**（标志性蓝项圈 + 白毛尖耳 + 啃骨头）
- **🐱 金渐层小猫**（圆脸祖母绿大眼 + 环纹绒尾 + 吃小鱼干）
- **🐕 拉布拉多小狗**（奶油米白短毛 + 暖杏金耷拉耳 + 金焦糖尾尖 + 啃骨头）
- **🐈 金吉拉小猫**（雪白长毛银背影 + 黑眼线绿宝石大眼 + 蓬松羽绒尾 + 吃小鱼干）
- 顶部菜单栏 / 系统托盘头像、零食道具、咀嚼碎屑、网球对手与赛况文案全部随角色实时联动。

### 2. 极简爬顶 + 7 组独立顶栏特效（右键一级菜单直达）
- **极简初始趴窗姿态**：从屏幕右侧爬上窗口顶栏后，搭爪探头左看右看并自然趴在窗口顶边朝前张望（下巴紧贴顶边零空隙）。
- **7 组完全独立的顶栏特效**（支持右键一级菜单随时单点播放，或在设置中自由勾选定时轮播）：
  1. **🐾 跳走巡逻**：3 帧欢快左跳 + 原地转头东张西望 + 4 帧四足小跑右走 → 微笑坐下
  2. **⚡ 闪身步**：8 帧 192×128 定高复刻经典反倾假动作 + 平移定格魔性舞步
  3. **🐻 狗熊哆嗦毛**：8 帧开腿举爪 + 额前交叉 `😮` 甩爪 + 斜向侧倾抖爪循环
  4. **⚽ 浪子踢球**：6 帧张臂起势 + 深蹲后勾蓄力 + 撇踢「W」手势帅气亮相（左右脚对称各一次）
  5. **🥺 歪头杀**：6 帧端坐前爪不动，多角度萌系歪头连击定格
  6. **🌀 翻肚皮打滚（点击互动）**：仰躺露肚皮等主人摸，**左键单击一次立刻翻滚到另一侧并冒 `💕`**，超过 10 秒未点击自动起身坐好
  7. **😴 打哈欠睡觉**：打大哈欠 → 犯困半眯 → 团成团子安稳入睡
- **专属投喂零食**：小狗投喂 `🦴 骨头饼干`、小猫投喂 `🐟 小鱼干`，伴随小跑追食、2 帧开心咀嚼与像素碎屑特效。

### 3. 零打扰默认配置 & 多屏顺滑体验
- **开箱即用默认节奏**（可在右键 `⚙️ 设置` 或偏好设置弹窗随时调整）：
  - 陪伴位置偏好：**屏幕右侧边 + 定时爬顶**
  - 换窗等待：**15 秒**（含叠窗提前隐藏与全屏原地平滑下缩）
  - 爬顶等待：**5 分钟**（支持 3 秒 ~ 60 分钟）
  - 特效间隔：**15 分钟**（支持 5 秒 ~ 1 小时或关闭）
  - 宠物大小：**150%**（支持 60% ~ 160% 实时缩放）
- 支持防误点高速划过害羞缩头、打字免打扰、会议免打扰、拎后颈阻尼弹簧拖拽，以及双屏/外接显示器自适应与渲染心跳守护。

### 4. 2.5D 桌面网球模式（`WASD` + 鼠标对打 · 四档球速）
- 直接在桌面中央展开半透明球场，支持三维 `(x, y, z)` 重力、球网判定、上旋蓄力/切削放小球/高吊球，默认 **`🐢 慢速`** 轻松上手（`慢速 / 适中 / 标准 / 快速` 可调）。
- **操作指南（基于硬件键码，兼容中文输入法）**：
  | 操作 | 效果 |
  | :--- | :--- |
  | **`W / A / S / D`**（或方向键） | 控制底线球员前后左右跑位 |
  | **双击方向键 / `Space`** | 飞身冲刺救大角度球 |
  | **鼠标移动** | 移动对面半场的落点准星 |
  | **鼠标左键点按 / 长按蓄力** | 快速平击抽球 / 强力上旋抽球 / 发球 |
  | **鼠标右键点击** | 瞄近网为 **切削放小球（Drop Shot）**；瞄底线为 **高吊球（Lob）** |
  | **`-` / `=`（或 `[` / `]`）** | 实时调慢 / 调快网球球速 |
  | **`R` / 左键（赛末）** | 重新开球再来一局 |
  | **`ESC` / `⌘⇧T`** | 收起球场回到桌面陪伴 |

---

## 🚀 快速安装与运行

### 方式 A：直接从 GitHub Releases 下载免编译版本（推荐）
前往本仓库的 **[Releases](https://github.com/joeyzenghuan/westie-desk-pet/releases)** 页面：
- **Windows 10/11 (x64)**：下载 `WestieDeskPet-Windows-x64.zip`，解压后直接双击 `WestieDeskPet.exe` 即可运行（已内置 .NET 8 运行时，免装环境）。
- **macOS (Apple Silicon / macOS 14+)**：下载 `WestieDeskPet-macOS.zip` 解压得到 `WestieDeskPet.app`（首次打开如遇未签名提示可执行 `xattr -dr com.apple.quarantine WestieDeskPet.app` 后双击打开），或按下方方式 B 本地 1 分钟原生编译。

---

### 方式 B：从源码一键本地构建安装

#### macOS（Swift 6 + AppKit + SpriteKit）
环境要求：**macOS 14.0+** + Xcode Command Line Tools（如未安装运行 `xcode-select --install`）。

```bash
git clone https://github.com/joeyzenghuan/westie-desk-pet.git
cd westie-desk-pet

# 1. 运行内置 50 项自检（可选）
swift run WestieDeskPet --self-test

# 2. 编译打包独立应用（输出 dist/WestieDeskPet.app）
./scripts/build_app.sh

# 3. 安装到「应用程序」目录并启动（常驻顶部菜单栏，不占 Dock）
rm -rf /Applications/WestieDeskPet.app && cp -R dist/WestieDeskPet.app /Applications/
open /Applications/WestieDeskPet.app
```

#### Windows 10 / 11（.NET 8 + WPF + Win32 DWM）
环境要求：**Windows 10/11 (x64)** + [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)（可用 `winget install Microsoft.DotNet.SDK.8` 一键安装）。

```powershell
git clone https://github.com/joeyzenghuan/westie-desk-pet.git
cd westie-desk-pet

# 运行测试并打包单文件便携版（含 .NET 运行时，输出 dist\windows-win-x64\WestieDeskPet.exe）
.\scripts\build_windows.ps1 -Runtime win-x64 -SelfContained

# 启动桌面伙伴（常驻右下角系统托盘）
Start-Process .\dist\windows-win-x64\WestieDeskPet.exe
```

也支持在 macOS 上交叉编译 Windows 版：

```bash
./scripts/build_windows_from_mac.sh win-x64 false
```

---

## 🎨 像素资产生成脚本（开发者可选）

全部 274 张透明像素精灵已直接打包在 `Sources/WestieDeskPet/Resources/Sprites/` 中，**日常编译与使用无需任何 API Key**。如需用 Azure OpenAI 图像模型二次扩展新宠物或新动作，可参考 `scripts/generate_*.py`（通过 `AZURE_OPENAI_ENDPOINT` 与 `AZURE_OPENAI_API_KEY` 环境变量传入凭据）。
