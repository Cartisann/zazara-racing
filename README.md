# ZAZARA RACING

赛道 GPS 蓝牙连接 App。SwiftUI + CoreBluetooth，iOS 原生浅色界面与 ZAZARA 红色品牌色。

![ZAZARA RACING UI](Design/zazara-racing-ui.png)

![语言切换 / Language setting](Design/zazara-language-setting.png)

## 语言 / Language

- 底部 `More / 更多` → `Language / 语言`
- 支持 `English` 与 `简体中文` 即时切换，整个 App 的标题、按钮、状态、日期和错误提示都会同步切换
- 首次启动默认跟随系统语言；手动选择后会保存到本机
- 蓝牙设备名称保持原样，便于识别硬件

## iPhone Duo

![iPhone Duo adaptive layout](Design/zazara-duo-ui.png)

- 外屏 `466 × 678`：四个 Tab 竖排在右下角的悬浮玻璃胶囊里，Connect Now 不会被遮挡
- 内屏竖屏 `669 × 951`：居中内容列，底部悬浮玻璃 Tab 间距加大
- 内屏横屏 `951 × 669`：四个 Tab 变成右下角悬浮的 Liquid Glass 胶囊，和系统状态栏同一列；Devices 页使用双列布局（连接面板 + 蓝牙记录）
- 普通 iPhone 竖屏：底部悬浮 Liquid Glass 胶囊；Duo 外屏：右下角竖向玻璃 Tab 胶囊
- 分屏/半折叠状态会按可用宽度自动切换单列或双列；安全区由系统处理
- 当前构建仍使用 Xcode 15.2 / iOS 17.2 SDK，因此没有使用 iOS 27 专属的 `ArrangementView` API，而是用标准 SwiftUI 宽高断点实现

> **关于旧 SDK 的小屏窗口**：iOS 会根据二进制的 `LC_BUILD_VERSION` SDK 版本决定 iPhone Duo 是否使用完整内屏。Xcode 15.2 产物默认会被系统放在一个手机比例的居中窗口里。`Scripts/make-unsigned-ipa.sh` 会在编译后用 `vtool` 将 SDK 标记为 27.1，供 Sideloadly 测试；这是非官方 workaround。若系统仍然显示小屏窗口，必须用 Xcode 27.1 / iOS 27.1 SDK 重新构建。

## 核心流程

1. 启动进入 **Devices** 设备管理页；底部为 `DRAG / TRACK / DEVICES / MORE` 四个 Tab。
2. 没有记录时显示红色空状态，点击 **Connect Now** 扫描附近 Bluetooth LE GPS 模块。
3. 每次配对成功都会保存一条 **Bluetooth Records** 记录，支持保存多个不同的 GPS 模块；未连接的记录置灰显示，点击 **Connect** 即可重新连接。
4. 连接成功后展示 **Signal Locked** 页面，包含模块名、信号、电量（若模块支持 Battery Service）和连接状态。
5. 返回 Devices 页后，顶部会出现实时链路卡片，当前模块在记录列表中标记为 `Connected`；其他记录仍可查看，断开后可切换。
6. `Drag` 和 `Track` 为后续计时功能占位页；`More` 提供蓝牙状态、记录数量、清除记录和版本信息。

## 已实现

- CoreBluetooth 扫描 / 连接 / 断开 / 超时处理
- 附近模块实时 RSSI 与信号格
- 多条蓝牙记录持久化（UserDefaults），最多保存 12 个不同模块
- 未连接记录置灰，带独立 `Connect` 操作；当前连接记录高亮为 `Connected`
- 长按记录可删除；More 页可一次清除全部记录
- 断线、蓝牙关闭、权限被拒、找不到设备等状态提示
- 连接成功后读取 Battery Service（180F / 2A19，可选）
- 应用内中英文即时切换，设置本地持久化
- iPhone Duo 外屏、内屏竖屏、内屏横屏与分屏的自适应布局
- 横屏右下角悬浮玻璃 Tab、竖屏底部玻璃 Tab、双列 Devices 布局（使用 Material 近似 Liquid Glass；当前 SDK 17.2 无原生 glassEffect API）
- SwiftUI Previews 覆盖首次启动、记录、扫描、已连接、连接成功等状态
- 浅色状态栏、红色 Accent Color、蓝牙权限文案与 Sideloadly 安装脚本已配置

## 运行

- 使用 Xcode 15+ 打开 `ZAZARA RACING.xcodeproj`
- 最低系统：iOS 17.2
- **蓝牙 LE 在模拟器中不可用，请使用真机测试配对流程**
- 首次点击添加 GPS 时会请求蓝牙权限

> Xcode 15.2 无法直接连接 iPhone 16 Pro Max（iOS 18+）进行调试，会报
> `kAMDMobileImageMounterPersonalizedBundleMissingVariantError`。
> 下面提供 Sideloadly 临时安装方式。

## 临时真机安装（Sideloadly + 免费 Apple ID）

已生成现成安装包：

`build/ZAZARA-RACING-unsigned.ipa`

重新生成：

```bash
./Scripts/make-unsigned-ipa.sh
```

该 IPA 使用 iOS 17.2 SDK、arm64，已做 ad-hoc 签名；Sideloadly 会使用你的免费 Apple ID 重新签名后安装。

1. 在 Mac 安装 [Sideloadly](https://sideloadly.io)。（若捆绑 ID 冲突，在 Sideloadly 中勾选 Change Bundle ID。）
2. 用 USB 连接 iPhone 16 Pro Max，在手机上选择“信任此电脑”。
3. 在 iPhone 的 `设置 → 隐私与安全性 → 开发者模式` 打开开发者模式并重启。这个入口通常需要先尝试安装一次才会出现。
4. 把 `build/ZAZARA-RACING-unsigned.ipa` 拖进 Sideloadly，输入 Apple ID 和密码（或 App 专用密码），完成双重验证。
5. 安装完成后，在 iPhone 的 `设置 → 通用 → VPN 与设备管理` 中信任对应开发者证书。
6. 打开 **ZAZARA RACING**，允许蓝牙权限，点击 `Connect Now` 开始扫描。

注意事项：

- 免费 Apple ID 签名的 App **7 天后过期**；重新用 Sideloadly 安装一次即可刷新。
- 这种方式不能连接 Xcode 调试器，也看不到设备控制台日志。
- 测试包的 Bundle ID 是 `com.zazara.racing`；以后使用 Xcode 正式安装时会是独立的应用记录。
- Sideloadly 需要 Apple ID 凭据在本机完成签名，不会由项目或脚本保存。不要把 Apple ID 密码发给其他人。
- 该 IPA 用 iOS 17.2 SDK 构建。如果未来 iPhone 系统版本拒绝启动旧 SDK 包，需要改用云 Mac/CI + 当前版本 Xcode 重新构建。

## 说明

- 当前只建立 Bluetooth LE 链路并读取通用电量服务。不同 GPS 厂商的定位/速度协议（RaceBox、VBOX 等）不同，后续需要在连接成功后按厂商协议订阅数据。
- Drag / Track 目前是视觉占位页，还没有计时或赛道数据逻辑。
- 经典蓝牙（Bluetooth Classic / SPP）模块不会被 CoreBluetooth 扫描到，需要 MFi ExternalAccessory 方案。
- 历史记录只保存在当前设备上，不跨设备同步。
- 界面支持应用内中英文切换；蓝牙权限系统弹窗仍由 iOS 根据系统语言显示。

## 代码结构

- `Localization.swift` — 中英文文案、语言偏好与日期本地化
- `DesignSystem.swift` — 浅色主题、红色按钮/卡片、Tab 栏、通用组件
- `GPSLinkManager.swift` — CoreBluetooth 状态机、历史记录、RSSI/电量
- `ConnectGPSView.swift` — Devices 页、扫描、附近设备、蓝牙记录、连接卡片
- `LinkedView.swift` — Signal Locked 连接成功页
- `AppShellView.swift` — 四个 Tab、Drag / Track / More 页面、语言设置、Duo 横屏悬浮玻璃 Tab
- `ContentView.swift` / `ZAZARA_RACINGApp.swift` — App 入口与环境注入
- `Scripts/make-unsigned-ipa.sh` — 不依赖 Xcode 设备调试，生成可交给 Sideloadly 的 IPA
