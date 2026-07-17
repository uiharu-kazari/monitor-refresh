# MonitorRefresh

[English](README.md) | **简体中文**

一个极简的 macOS 菜单栏小工具：当外接显示器黑屏、半屏不亮或"卡住"时，**无需拔插任何线缆**，点一下菜单即可恢复。它通过视频线向显示器发送 DDC 电源循环指令——相当于用软件按了一下显示器的电源键。

## 为什么会有这个工具

有些外接显示器会偶尔丢失部分画面，必须物理拔插线缆才能恢复。这在**上下双屏叠放式便携显示器**（如 EHOMEWEI X 系列、JSAUX FlipGo 等）上尤其常见：显示器内部负责把一路视频信号拆分到两块面板的控制芯片卡死，导致半边屏幕变黑或变暗。

从 Mac 这一侧重新握手视频信号（改分辨率、休眠显示器、甚至软件断开重连）通常**无法**解决，因为故障出在显示器自己的控制器里。真正有效的是给显示器断电重启——而这其实可以用软件做到：大多数显示器支持通过视频线接收 DDC/CI 的 `powerMode` 指令（VCP `0xD6`）。

本工具把这个修复做成了菜单栏里的一次点击。它最初是为一台 EHOMEWEI 双叠屏便携显示器（在 macOS 中显示为 "LINK"）开发的——其上半屏经常熄灭，DDC 电源循环可以稳定地将其唤醒。

## 系统要求

- macOS 13 或更高版本（Apple Silicon 和 Intel 均可）
- 已在 `/Applications` 安装 [BetterDisplay](https://github.com/waydabber/BetterDisplay)（免费版即可）。MonitorRefresh 通过 BetterDisplay 的命令行接口与显示器进行 DDC 通信。
- 编译需要 Xcode 命令行工具（`xcode-select --install`）

## 安装

```sh
git clone https://github.com/uiharu-kazari/monitor-refresh.git
cd monitor-refresh
./build.sh
open ~/Applications/MonitorRefresh.app
```

开机自启动：系统设置 → 通用 → 登录项 → 添加 **MonitorRefresh**，或执行：

```sh
osascript -e 'tell application "System Events" to make new login item at end with properties {path:"'$HOME'/Applications/MonitorRefresh.app", hidden:true}'
```

## 使用方法

点击菜单栏中的显示器图标：

- **Power Cycle "\<显示器名\>"** — 每台已连接的显示器各有一项。发送 DDC 关机指令，等待 6 秒后再发送开机指令。显示器会短暂黑屏，随后带着复位后的控制器恢复画面。这是主要的修复手段。
- **Advanced（高级）→**
  - **Disconnect & Reconnect（断开并重连）** — 软件层面的拔插：macOS 完全移除该显示器后重新添加（真正的热插拔事件）。注意：可能会打乱窗口位置，且断开功能可能需要 BetterDisplay Pro。
  - **Sleep & Wake All Displays（休眠并唤醒所有显示器）** — 强制所有显示器经历一次休眠/唤醒握手。
- 修复执行期间，图标会变成沙漏。

每次打开菜单都会重新枚举显示器，新接入的显示器会自动出现。

## 只想用 shell 脚本？

如果不需要菜单栏应用，应用的全部功能也提供了独立脚本版本：[`scripts/monitor-refresh.sh`](scripts/monitor-refresh.sh)。只依赖 zsh 和 BetterDisplay，无需编译。

```sh
./scripts/monitor-refresh.sh --list             # 列出已连接的显示器名称
./scripts/monitor-refresh.sh "LINK"             # 对该显示器执行 DDC 电源循环（主要修复手段）
./scripts/monitor-refresh.sh "LINK" --reconnect # 改用软件层面的断开重连
./scripts/monitor-refresh.sh --hard             # 所有显示器休眠 5 秒后唤醒
```

先用 `--list` 查到显示器的准确名称，再把名称作为参数执行电源循环。电源循环会发送 DDC 关机指令、等待 6 秒、再发送开机指令——显示器短暂黑屏后，内部控制器即被复位。适合配合快捷启动工具（Raycast、Alfred）、`ssh` 或 cron 使用。

## 工作原理

- 显示器枚举和 DDC 指令均通过 BetterDisplay 命令行完成（`BetterDisplay get -identifiers`、`BetterDisplay set -name=... -ddc -vcp=powerMode -value=4/1`）。
- 经过 DP→HDMI 转换器或扩展坞时 DDC 信号不稳定，因此每条 DDC 指令最多自动重试 5 次。
- 应用本体仅约 200 行 Swift（`Sources/main.swift`），直接用 `swiftc` 编译——无 Xcode 工程、无第三方依赖、仅驻留菜单栏（无 Dock 图标）。

## 常见问题

- **提示 "No displays found"** — 请确认 BetterDisplay.app 已安装在 `/Applications` 并正在运行。
- **电源循环没有效果** — 你的显示器可能未实现 VCP `0xD6`。可用 `BetterDisplay get -name=<名称> -ddcCapabilities` 查看。部分显示器的"关机"只是关闭背光而非真正断电，这种情况下仍需使用物理电源键，或在供电线上加一个带开关的 USB-C 转接头作为替代方案。
- **显示器经过扩展坞/转换器连接** — DDC 通常仍可透传，但如果所有指令都失败，请尝试直连。

## 许可证

[MIT](LICENSE)
