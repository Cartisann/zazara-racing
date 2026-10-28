//
//  Localization.swift
//  ZAZARA RACING
//
//  Lightweight in-app English / Simplified Chinese localization.
//

import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var isChinese: Bool {
        self == .chinese
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        }
    }

    private static let storageKey = "zazara.appLanguage"

    init(language: AppLanguage? = nil) {
        if let language {
            self.language = language
            return
        }

        if
            let saved = UserDefaults.standard.string(forKey: Self.storageKey),
            let savedLanguage = AppLanguage(rawValue: saved)
        {
            self.language = savedLanguage
        } else {
            let preferred = Locale.preferredLanguages.first ?? "en"
            self.language = preferred.lowercased().hasPrefix("zh") ? .chinese : .english
        }
    }

    var locale: Locale {
        language.locale
    }

    // MARK: - Strings

    func t(_ key: String) -> String {
        Self.translate(key, language: language)
    }

    static func translate(_ key: String, language: AppLanguage) -> String {
        guard language == .chinese else { return key }
        return chinese[key] ?? key
    }

    func t(_ key: String, _ args: CVarArg...) -> String {
        let format = t(key)
        return String(format: format, locale: language.locale, arguments: args)
    }

    func savedRecordSubtitle(_ count: Int) -> String {
        if language.isChinese {
            return "已保存 \(count) 条蓝牙记录"
        }
        return "\(count) saved Bluetooth record\(count == 1 ? "" : "s")"
    }

    func savedCountText(_ count: Int) -> String {
        language.isChinese ? "已保存 \(count) 条" : "\(count) saved"
    }

    func foundCountText(_ count: Int) -> String {
        language.isChinese ? "找到 \(count) 台" : "\(count) found"
    }

    func devicesInRangeText(_ count: Int) -> String {
        if language.isChinese {
            return "附近有 \(count) 台设备"
        }
        return "\(count) device\(count == 1 ? "" : "s") in range"
    }

    func signalLabel(level: Int) -> String {
        switch level {
        case 4: return t("Excellent")
        case 3: return t("Good")
        case 2: return t("Fair")
        case 1: return t("Weak")
        default: return t("Measuring")
        }
    }

    // MARK: - Dates

    func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = language.isChinese ? "yyyy年M月d日" : "dd MMM yyyy"
        let text = formatter.string(from: date)
        return language.isChinese ? text : text.uppercased()
    }

    func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    func timeWithSecondsText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    func lastLinkedText(_ date: Date) -> String {
        t("Last linked %@", "\(dateText(date)) · \(timeWithSecondsText(date))")
    }

    func linkedText(_ date: Date) -> String {
        t("Linked %@ · %@", dateText(date), timeText(date))
    }

    static func localizedStatus(for manager: GPSLinkManager, language: AppLanguage) -> (text: String, color: Color) {
        if manager.isConnected {
            return (L10n.text("Connected", language: language), .zzGreen)
        }
        if manager.isConnecting {
            return (L10n.text("Connecting", language: language), .zzAmber)
        }
        if manager.isScanning {
            return (L10n.text("Scanning", language: language), .zzRed)
        }

        switch manager.bluetoothState {
        case .poweredOn:
            return (L10n.text("Bluetooth on", language: language), .zzGreen)
        case .poweredOff:
            return (L10n.text("Bluetooth off", language: language), .zzRed)
        case .unauthorized:
            return (L10n.text("Permission needed", language: language), .zzRed)
        case .unsupported:
            return (L10n.text("Bluetooth unavailable", language: language), .zzTertiary)
        case .resetting:
            return (L10n.text("Bluetooth resetting", language: language), .zzAmber)
        case .unknown:
            return (L10n.text("Bluetooth", language: language), .zzTertiary)
        @unknown default:
            return (L10n.text("Bluetooth", language: language), .zzTertiary)
        }
    }

    // MARK: - Dictionaries

    private static let chinese: [String: String] = [
        // Tabs and page titles
        "DRAG": "直线",
        "TRACK": "赛道",
        "DEVICES": "设备",
        "MORE": "更多",
        "TIMING": "计时",
        "MINE": "我的",
        "Drag": "直线加速",
        "Track": "赛道",
        "Devices": "设备",
        "More": "更多",
        "Timing": "计时",
        "Mine": "我的",
        "Quarter-mile performance": "四分之一英里性能",
        "Circuit sessions and lap timing": "赛道圈速与计时",
        "App settings and information": "应用设置与信息",
        "Bluetooth GPS modules": "蓝牙 GPS 模块",
        "Scanning for nearby GPS modules": "正在扫描附近的 GPS 模块",
        "Scanning for nearby ZAZARA GPS": "正在扫描附近的 ZAZARA GPS",
        "%@ connected": "%@ 已连接",

        // Track dashboard
        "Overview": "总览",
        "Dashboard": "仪表",
        "G-Force": "G 值",
        "Lateral": "横向",
        "Longitudinal": "纵向",
        "Speed": "速度",
        "No G data yet": "暂无 G 值数据",
        "Route": "路程",
        "No route data yet": "暂无路程数据",

        // Devices
        "Add GPS device": "添加 GPS 设备",
        "Stop scanning": "停止扫描",
        "Bluetooth is off": "蓝牙已关闭",
        "Turn on Bluetooth, then connect your GPS module.": "请打开蓝牙，然后连接 GPS 模块。",
        "Open Settings": "打开设置",
        "Bluetooth access needed": "需要蓝牙权限",
        "Allow Bluetooth access so ZAZARA RACING can find your GPS module.": "请允许蓝牙访问，以便 ZAZARA RACING 查找 GPS 模块。",
        "Bluetooth LE unavailable": "蓝牙 LE 不可用",
        "This device can’t scan for Bluetooth GPS modules.": "此设备无法扫描蓝牙 GPS 模块。",
        "No devices connected": "未连接设备",
        "Connect a Bluetooth GPS receiver to get started.": "连接蓝牙 GPS 接收器以开始。",
        "Connect a ZAZARA GPS receiver to get started.": "连接 ZAZARA GPS 接收器以开始。",
        "Connect Now": "立即连接",
        "Multiple GPS modules can be saved as records.": "可保存多个 GPS 模块记录。",
        "Scanning for GPS": "正在扫描 GPS",
        "Listening for Bluetooth LE devices": "正在搜索蓝牙 LE 设备",
        "Keep your GPS module powered on and within 3 m.": "请保持 GPS 模块开机，并保持在 3 米范围内。",
        "Stop": "停止",

        // Live / records
        "Connected": "已连接",
        "Last linked %@": "上次连接 %@",
        "Details": "详情",
        "Disconnect": "断开连接",
        "Signal": "信号",
        "Battery": "电量",
        "Link": "连接",
        "Excellent": "极佳",
        "Good": "良好",
        "Fair": "一般",
        "Weak": "较弱",
        "Measuring": "测量中",
        "Percent": "百分比",
        "Active": "已激活",
        "Bluetooth records": "连接记录",
        "Connection records": "连接记录",
        "Disconnect to switch": "断开后可切换",
        "Connect": "连接",
        "Nearby devices": "附近设备",
        "Nearby ZAZARA GPS": "附近的 ZAZARA GPS",
        "New ZAZARA GPS": "新的 ZAZARA GPS",
        "Last scan": "上次扫描",
        "Searching for GPS modules": "正在搜索 GPS 模块",
        "Searching for ZAZARA GPS": "正在搜索 ZAZARA GPS",
        "Only ZAZARA RACING GPS modules are shown.": "仅显示 ZAZARA RACING GPS 模块。",
        "Listening for ZAZARA GPS": "正在监听 ZAZARA GPS",
        "Powered on? Within 3 metres?": "已开机？在 3 米内？",
        "Bluetooth LE": "蓝牙 LE",
        "SAVED": "已保存",
        "Saved": "已保存",
        "Available": "可连接",
        "Available to connect": "可连接",
        "Forget record": "删除记录",
        "Delete": "删除",
        "Connects to this GPS module": "连接此 GPS 模块",
        "Connects to this saved GPS module": "连接此已保存的 GPS 模块",
        "Disconnect the active GPS module before connecting another": "请先断开当前 GPS 模块，再连接其他设备",
        "%@, nearby GPS device": "%@，附近的 GPS 设备",
        "%@, connection record": "%@，连接记录",
        "Signal strength %d of 4": "信号强度 %d/4",

        // Status
        "Bluetooth on": "蓝牙已开启",
        "Bluetooth off": "蓝牙已关闭",
        "Permission needed": "需要权限",
        "Bluetooth unavailable": "蓝牙不可用",
        "Bluetooth resetting": "蓝牙重置中",
        "Bluetooth": "蓝牙",
        "Connecting": "连接中",
        "Scanning": "扫描中",

        // Connecting overlay
        "Keep the module close to your phone.": "请将模块靠近手机。",
        "Cancel": "取消",

        // Alerts
        "Bluetooth access required": "需要蓝牙权限",
        "Allow Bluetooth access in Settings, then try linking your GPS module again.": "请在设置中允许蓝牙访问，然后重试连接 GPS 模块。",
        "Turn on Bluetooth, then try linking your GPS module again.": "请打开蓝牙，然后重试连接 GPS 模块。",
        "This device can’t connect to Bluetooth LE modules.": "此设备无法连接蓝牙 LE 模块。",
        "Bluetooth is not ready. Try again in a moment.": "蓝牙还未准备好，请稍后再试。",
        "Bluetooth not ready": "蓝牙未就绪",
        "Turn on Bluetooth and try linking again.": "请打开蓝牙后重试连接。",
        "Allow Bluetooth access in Settings to link your GPS module.": "请在设置中允许蓝牙访问，以连接 GPS 模块。",
        "Turn on Bluetooth, then try linking again.": "请打开蓝牙后重试连接。",
        "Give Bluetooth a moment, then try again.": "请稍候，再试一次。",
        "Your GPS module": "你的 GPS 模块",
        "Link timed out": "连接超时",
        "%@ didn’t respond. Power the module on, keep it close, and try again.": "%@ 没有响应。请确认模块已开机、靠近手机后重试。",
        "Link failed": "连接失败",
        "Couldn’t establish a link with %@. Move closer and try again.": "无法连接 %@。请靠近后重试。",
        "Unsupported GPS module": "不支持的 GPS 模块",
        "This device isn’t a ZAZARA GPS module.": "此设备不是 ZAZARA GPS 模块。",
        "Link interrupted": "连接中断",
        "The connection to %@ was interrupted. Try linking again.": "%@ 的连接已中断，请重试。",
        "Link lost": "连接已断开",
        "%@ disconnected. Power the module on and link again.": "%@ 已断开。请开机后重新连接。",
        "%@ disconnected because Bluetooth is unavailable. Reconnect to continue.": "%@ 已断开，因为蓝牙不可用。请重新连接。",

        // Mine
        "Language": "语言",
        "App language": "界面语言",
        "Changes apply immediately throughout the app.": "切换后立即应用到整个应用。",
        "GPS connection": "GPS 连接",
        "Account": "账户",
        "Not signed in": "未登录",
        "Not connected": "未连接",
        "GPS": "GPS",
        "Camera": "相机",
        "Settings": "设置",
        "Saved records": "已保存记录",
        "None": "无",
        "Delete all devices": "删除所有设备",
        "Delete all devices?": "删除所有设备？",
        "Delete all": "全部删除",
        "This removes every saved device and disconnects the active GPS module.": "这会从此 iPhone 上删除所有已保存的设备，并断开当前连接的 GPS 模块。",
        "Deleting devices disconnects the active GPS module.": "删除设备会断开当前已连接的 GPS 模块。",
        "Clear all saved records": "清除所有已保存记录",
        "Clearing records does not disconnect the active GPS module.": "清除记录不会断开当前连接的 GPS 模块。",
        "About": "关于",
        "Version": "版本",
        "Protocol": "协议",
        "TRACK GRADE GPS LINK": "赛道级 GPS 连接",
        "Clear all saved connection records?": "清除所有已保存的连接记录？",
        "This removes every saved GPS record from this iPhone.": "这会从此 iPhone 上删除所有已保存的 GPS 记录。",
        "Clear records": "清除记录",

        // Timing / Track
        "Straight-line acceleration": "直线加速",
        "COMING SOON": "即将推出",
        "Add": "添加",
        "Back": "返回",
        "Save": "保存",
        "By speed": "按速度",
        "By distance": "按距离",
        "Add by speed": "按速度添加",
        "Add by distance": "按距离添加",
        "Start speed": "起点速度",
        "End speed": "终点速度",
        "Start distance": "起点距离",
        "End distance": "终点距离",
        "Only numbers are allowed.": "只能输入数字。",
        "1/4 mile": "1/4英里",
        "Drag timing is next": "直线计时即将推出",
        "Connect a Bluetooth GPS receiver to unlock 0–100, quarter-mile and trap-speed runs.": "连接蓝牙 GPS 接收器，解锁 0–100、四分之一英里和尾速测试。",
        "Connect a GPS device": "连接 GPS 设备",
        "NEXT MILESTONE": "下一阶段",
        "Track sessions are next": "赛道计时即将推出",
        "Track library and lap timing": "赛道库与圈速计时",
        "Track library is coming soon": "赛道库即将上线",
        "Connect a Bluetooth GPS receiver to record circuits, lap times and session history.": "连接蓝牙 GPS 接收器，记录赛道、圈速和会话历史。",
        "GPS receiver": "GPS接收器",
        "Time": "时间",
        "Satellites": "卫星数量",
        "Coordinate error": "坐标误差",
        "Fix type": "定位类型",
        "Heading": "方位角",
        "Altitude": "海拔",
        "Altitude error": "海拔误差",
        "Latitude": "纬度",
        "Longitude": "经度",
        "Elapsed time": "经过时间",
        "Distance": "路程",
        "Vehicle speed": "车辆速度",
        "SVs": "星数",
        "Edit": "编辑",
        "Done": "完成",
        "Drag tiles to reorder": "拖动方块调整位置",

        // Success
        "Signal locked": "信号已锁定",
        "%@ is connected and ready.": "%@ 已连接，准备就绪。",
        "Hold the signal": "保持信号",
        "Keep the receiver powered and within 3 m. Link health refreshes every few seconds.": "请保持接收器开机，并保持在 3 米范围内。连接状态会持续刷新。",
        "Back to Devices": "返回设备",
        "Back to devices": "返回设备",
        "Linked %@ · %@": "连接于 %@ · %@",
        "LIVE": "实时",
        "Returns to the devices list and keeps the link active": "返回设备列表并保持连接",
        "Disconnects the GPS module": "断开 GPS 模块"
    ]
}

enum L10n {
    static func text(_ key: String, language: AppLanguage) -> String {
        AppSettings.translate(key, language: language)
    }

    static func text(_ key: String, language: AppLanguage, _ args: CVarArg...) -> String {
        let format = text(key, language: language)
        return String(format: format, locale: language.locale, arguments: args)
    }
}
