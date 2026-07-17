# MonitorRefresh

[English](README.md) | **简体中文**

一个极简的 macOS 菜单栏小工具：当外接显示器黑屏、半屏不亮或"卡住"时，**无需拔插任何线缆**，点一下菜单即可恢复。它通过视频线向显示器发送 DDC 电源循环指令——相当于用软件按了一下显示器的电源键。

**零依赖。** 应用直接通过系统 IOKit 与显示器进行 DDC/CI 通信（与 [m1ddc](https://github.com/waydabber/m1ddc)、[MonitorControl](https://github.com/MonitorControl/MonitorControl) 采用相同机制）。

## 为什么会有这个工具

有些外接显示器会偶尔丢失部分画面，必须物理拔插线缆才能恢复。这在**上下双屏叠放式便携显示器**（如 EHOMEWEI X 系列、JSAUX FlipGo 等）上尤其常见：显示器内部负责把一路视频信号拆分到两块面板的控制芯片卡死，导致半边屏幕变黑或变暗。

从 Mac 这一侧重新握手视频信号（改分辨率、休眠显示器、甚至软件断开重连）通常**无法**解决，因为故障出在显示器自己的控制器里。真正有效的是给显示器断电重启——而这其实可以用软件做到：大多数显示器支持通过视频线接收 DDC/CI 的 `powerMode` 指令（VCP `0xD6`）。

本工具把这个修复做成了菜单栏里的一次点击。它最初是为一台 EHOMEWEI 双叠屏便携显示器（在 macOS 中显示为 "LINK"）开发的——其上半屏经常熄灭，DDC 电源循环可以稳定地将其唤醒。

## 系统要求

- **Apple Silicon** 芯片的 Mac（M1 或更新）
- macOS 13 或更高版本
- 仅此而已——无需驱动，无需任何辅助软件。

## 安装

### 方式 A：下载 DMG

从 [Releases](https://github.com/uiharu-kazari/monitor-refresh/releases) 下载最新的 `MonitorRefresh-x.y.z.dmg`，打开后把 **MonitorRefresh** 拖入"应用程序"文件夹。

由于这是没有 Apple 开发者证书的免费开源应用，首次启动会被 macOS 拦截。请在 **系统设置 → 隐私与安全性 → "仍要打开"** 中放行一次，或在终端清除隔离标记：

```sh
xattr -cr /Applications/MonitorRefresh.app
```

### 方式 B：从源码构建

需要 Xcode 命令行工具（`xcode-select --install`）。自己构建的应用不带隔离标记，不会弹安全提示。

```sh
git clone https://github.com/uiharu-kazari/monitor-refresh.git
cd monitor-refresh
./build.sh
open ~/Applications/MonitorRefresh.app
```

### 开机自启动

系统设置 → 通用 → 登录项 → 添加 **MonitorRefresh**，或执行：

```sh
osascript -e 'tell application "System Events" to make new login item at end with properties {path:"'$HOME'/Applications/MonitorRefresh.app", hidden:true}'
```

## 使用方法

点击菜单栏中"带刷新箭头的显示器"图标：

- **Power Cycle "\<显示器名\>"** — 每台已连接的显示器各有一项。发送 DDC 关机指令，等待 6 秒后再发送开机指令。显示器会短暂黑屏，随后带着复位后的控制器恢复画面。这是主要的修复手段。
- **Sleep & Wake All Displays（休眠并唤醒所有显示器）** — 强制所有显示器经历一次休眠/唤醒握手（更温和，适合应对其他类型的显示故障）。
- 修复执行期间，图标会变成沙漏。

每次打开菜单都会重新枚举显示器，新接入的显示器会自动出现。

菜单支持本地化：当系统语言为中文时显示**简体中文**，否则显示英文。若想在不更改系统语言的情况下预览中文菜单：

```sh
open -n ~/Applications/MonitorRefresh.app --args -AppleLanguages '(zh-Hans)'
```

## 命令行

应用二进制本身就是一个 CLI——适合配合 Raycast/Alfred 脚本、`ssh` 或 cron 使用：

```sh
APP=~/Applications/MonitorRefresh.app/Contents/MacOS/MonitorRefresh
$APP --list                  # 列出已连接的显示器名称
$APP --power-cycle "LINK"    # 对该显示器执行 DDC 电源循环
```

[`scripts/monitor-refresh.sh`](scripts/monitor-refresh.sh) 对其做了更简短的封装，并额外提供 `--hard`（休眠并唤醒所有显示器）：

```sh
./scripts/monitor-refresh.sh --list
./scripts/monitor-refresh.sh "LINK"
./scripts/monitor-refresh.sh --hard
```

## 工作原理

- 通过遍历 IORegistry 发现显示器：每台显示器的帧缓冲节点（携带产品名称）与其 `DCPAVServiceProxy` DDC 端点配对。
- 电源循环是一次 DDC/CI 的 *Set VCP Feature* 写入：`powerMode`（VCP `0xD6`）先写值 4（关机）、再写值 1（开机），经由私有 `IOAVService` API 走 I2C 发送。该方案已被 [m1ddc](https://github.com/waydabber/m1ddc) 和 [MonitorControl](https://github.com/MonitorControl/MonitorControl) 验证。
- 经过 DP→HDMI 转换器或扩展坞时 DDC 信号不稳定，因此每次 DDC 写入最多自动重试 5 次。
- 整个应用仅约 250 行 Swift（`Sources/main.swift`），直接用 `swiftc` 编译——无 Xcode 工程、无第三方依赖、仅驻留菜单栏（无 Dock 图标）。

## 常见问题

- **提示 "Unsupported system"** — 原生 DDC 通道需要 Apple Silicon。Intel Mac 请改用 [ddcctl](https://github.com/kfix/ddcctl) 等 DDC 工具。
- **电源循环没有效果** — 你的显示器可能未实现 VCP `0xD6`。部分显示器的"关机"只是关闭背光而非真正断电，这种情况下仍需使用物理电源键，或在供电线上加一个带开关的 USB-C 转接头作为替代方案。
- **显示器经过扩展坞/转换器连接** — DDC 通常仍可透传（本项目最初的问题显示器就接在 DP→HDMI 转换器后面，工作正常），但如果所有指令都失败，请尝试直连。

## 许可证

[MIT](LICENSE)
