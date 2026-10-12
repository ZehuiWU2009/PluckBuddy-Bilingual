//
//  Localization.swift
//  PluckBuddy
//
//  应用内中英双语支持：key 即中文原文，英文文案在 en.lproj/Localizable.strings。
//  取不到英文时回退为 key（即中文），因此中文环境无需单独建表。
//

import SwiftUI
import Combine

/// 应用内语言选项
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "auto"
    case zh = "zh-Hans"
    case en = "en"

    var id: String { rawValue }

    /// 选项标签固定用原生写法，便于用户识别
    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .zh:     return "中文"
        case .en:     return "English"
        }
    }
}

/// 语言管理器：持有当前 Bundle，切换时递增 token 触发界面重建
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @AppStorage("appLanguage") var selection: String = AppLanguage.system.rawValue
    @Published var token: Int = 0

    private var bundle: Bundle = .main

    var current: AppLanguage { AppLanguage(rawValue: selection) ?? .system }

    init() { reloadBundle() }

    /// 根据当前选择解析出要加载的 .lproj 标识
    private func resolvedLocaleID() -> String {
        switch current {
        case .system:
            let pref = Bundle.main.preferredLocalizations.first ?? "zh-Hans"
            return pref.hasPrefix("en") ? "en" : "zh-Hans"
        case .zh: return "zh-Hans"
        case .en: return "en"
        }
    }

    func reloadBundle() {
        let id = resolvedLocaleID()
        // 多种定位方式兜底，避免不同 Xcode 打包下 .lproj 目录结构差异导致取不到 bundle：
        // 1) 标准 .lproj bundle 路径；
        // 2) .lproj 目录内 Localizable.strings 的父目录；
        // 3) 直接用 resourceURL 拼 .lproj。
        let candidates: [String?] = [
            Bundle.main.path(forResource: id, ofType: "lproj"),
            Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: "\(id).lproj")
                .map { $0.deletingLastPathComponent().path },
            Bundle.main.resourceURL?.appendingPathComponent("\(id).lproj").path,
        ]
        for path in candidates.compactMap({ $0 }) {
            if let b = Bundle(path: path) {
                bundle = b
                return
            }
        }
        bundle = .main
    }

    /// 应用语言选择并通知界面重建
    func apply() {
        reloadBundle()
        token &+= 1
    }

    func localized(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

/// 取本地化字符串的便捷函数：L("弹拨搭子")
func L(_ key: String) -> String { LanguageManager.shared.localized(key) }
