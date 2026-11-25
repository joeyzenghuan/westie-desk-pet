# Westie Desk Pet 🐶🎾

一款原生轻量化 **macOS 西高地白梗（Westie）桌面陪伴 + 2.5D 网球对打** 小应用（Swift 6 + AppKit + SpriteKit，安装包体积 < 2 MB，无需辅助功能或录屏权限）。

平时它是一只像素风西高地小狗，会自动沿着你打开的各个窗口顶边散步、歪头坐下、打盹或跨窗口跳跃；想放松一局时，随时展开半透明桌面网球场，用 **`WASD` + 鼠标** 和戴着网球头带的西高地来一场 5 分制网球对决！

---

## ✨ 核心特性

### 1. 桌面窗口陪伴模式（零打扰 · 鼠标穿透）
- **零权限窗口顶边感知**：基于 `CGWindowListCopyWindowInfo` 实时提取屏幕上未被前层遮挡的窗口顶边作为 2D 平台，不申请录屏或辅助功能权限。
- **动态物理交互**：
  - **随窗平移**：拖动底层窗口时，趴在上面的西高地会稳稳跟着窗口移动。
  - **重力下落 & 跨窗跳跃**：关闭或最小化脚下窗口时，小狗会受重力下落到下方窗口或 Dock 地面；走到窗口边缘时还会计算抛物线跳向相邻窗口。
  - **鼠标精准穿透**：全屏无边框透明 `NSPanel` 默认完全穿透点击，不影响写代码和办公；只有鼠标移到小狗身上时才激活交互：
    - **悬停撸狗**：冒出粉色爱心 `♥` 并开心地歪头。
    - **左键拎后颈拖拽**：拎起小狗放到任意窗口顶边。
    - **右键快捷菜单 / 顶部菜单栏图标**：投喂骨头饼干 `🦴`、召唤到当前窗口 `🐾`、切换安静趴睡模式 `💤`、让小狗叼来网球邀战 `🎾`。
  - **专注邀战 & 会议免打扰**：检测到 Teams / Zoom 前台开会时自动安静趴睡；连续工作一段时间后会叼着绿色网球冒出 `🎾 来打网球!` 气泡（点击即开球，不点会自动放下继续陪跑）。

### 2. 2.5D 桌面网球模式（`WASD` + 鼠标对打）
- **GBA《马里奥网球》风格半透明球场**：直接在桌面中央展开，支持完整三维 `(x, y, z)` 重力、球网高度判定、旋转空气动力与单打边线/二跳得分规则。
- **操作指南（兼容中文输入法，基于硬件键码）**：
  | 操作 | 效果 |
  | :--- | :--- |
  | **`W / A / S / D`**（或方向键） | 控制底线球员前后左右跑位 |
  | **双击方向键 / `Space`** | 飞身冲刺救大角度球 |
  | **鼠标移动** | 移动对面半场的落点准星 |
  | **鼠标左键点按** | 快速平击抽球 / 发球 |
  | **鼠标左键按住蓄力松开** | 强力上旋抽球（过网急坠、落地加速） |
  | **鼠标右键点击** | 瞄近网为 **切削放小球（Drop Shot）**；瞄底线为 **高吊球（Lob）** |
  | **`R` / 左键（赛末）** | 重新开球再来一局 |
  | **`ESC` / 右上角按钮 / `⌘⇧T`** | 立即收起球场，西高地跳回刚才的窗口顶边 |
- **双难度西高地 AI**：可在球场左上角或菜单栏切换 **休闲小狗 (Casual)** 与 **网球狗王 (Pro，带飞身扑救与放小球战术)**。

---

## 🚀 构建与运行

环境要求：**macOS 14.0+**，安装 Xcode 或 Xcode Command Line Tools（Swift 6.0+）。

```bash
# 1. 运行内置物理、AI 与贴图资源自检
swift run WestieDeskPet --self-test

# 2. 打包独立 macOS 应用 (输出到 dist/WestieDeskPet.app)
./scripts/build_app.sh

# 3. 启动西高地桌面伙伴！（启动后常驻顶部菜单栏，不占 Dock 图标）
open dist/WestieDeskPet.app
```

也可以直接通过命令行参数直接进入网球模式调试：

```bash
swift run WestieDeskPet --tennis
```

---

## 🎨 AI 像素美术资产管线（Azure GPT-Image-2.5）

所有 18 张透明背景像素精灵与菜单栏/应用图标均由 `scripts/generate_assets.py` + `scripts/process_sprites.py` 自动生成与切图对齐（使用参考图锁定同一只蓝项圈西高地的角色一致性）：

```bash
export AZURE_OPENAI_ENDPOINT="https://<your-resource>.openai.azure.com"
export AZURE_OPENAI_API_KEY="<your-api-key>"

uv run --with pillow --with numpy python scripts/generate_assets.py
uv run --with pillow --with numpy python scripts/process_sprites.py
```
