//
//  KeywordSettings.swift
//  CoverZip
//
//  Created by Nihondo on 2025/07/19.
//

import Foundation

/**
 * キーワードタイプを表す列挙型
 */
enum KeywordType: String, Codable, CaseIterable {
    case filename      = "filename"   // ファイル名が
    case pathname      = "pathname"   // フォルダ名が（直接の親フォルダ名）
    case fileExtension = "extension"  // 拡張子が

    var displayName: String {
        switch self {
        case .filename:
            return CZLocalized.string("routing.rule.type.filename", defaultValue: "Filename")
        case .pathname:
            return CZLocalized.string("routing.rule.type.pathname", defaultValue: "Folder Name")
        case .fileExtension:
            return CZLocalized.string("routing.rule.type.extension", defaultValue: "File Extension")
        }
    }
}

/**
 * マッチング方式を表す列挙型
 */
enum MatchMode: String, Codable, CaseIterable {
    case contains   = "contains"    // 次を含む
    case startsWith = "startsWith"  // 次で始まる
    case endsWith   = "endsWith"    // 次で終わる
    case wildcard   = "wildcard"    // 次に一致（ワイルドカード）
    case regex      = "regex"       // 次に一致（正規表現）

    var displayName: String {
        switch self {
        case .contains:
            return CZLocalized.string("routing.rule.match.contains", defaultValue: "contains")
        case .startsWith:
            return CZLocalized.string("routing.rule.match.starts_with", defaultValue: "starts with")
        case .endsWith:
            return CZLocalized.string("routing.rule.match.ends_with", defaultValue: "ends with")
        case .wildcard:
            return CZLocalized.string("routing.rule.match.wildcard", defaultValue: "matches wildcard")
        case .regex:
            return CZLocalized.string("routing.rule.match.regex", defaultValue: "matches regex")
        }
    }
}

/**
 * 個別キーワードルールを表す構造体（配列用）
 */
struct KeywordRule: Codable, Identifiable {
    var id: UUID
    var keyword: String
    var type: KeywordType
    var application: String
    var matchMode: MatchMode

    init(id: UUID = UUID(), keyword: String, type: KeywordType, application: String, matchMode: MatchMode = .contains) {
        self.id = id
        self.keyword = keyword
        self.type = type
        self.application = application
        self.matchMode = matchMode
    }
}

/**
 * ファイルルーティング設定モデル（配列ベース）
 */
struct KeywordSettings: Codable {
    var rules: [KeywordRule]
    var defaultApplication: String

    static let defaultSettings = KeywordSettings(
        rules: [],
        defaultApplication: ""
    )

    static let sampleSettings = KeywordSettings(
        rules: [
            KeywordRule(keyword: "コミック", type: .filename, application: "internal", matchMode: .contains),
            KeywordRule(keyword: "manga", type: .filename, application: "internal", matchMode: .contains),
            KeywordRule(keyword: "vol*", type: .filename, application: "internal", matchMode: .wildcard)
        ],
        defaultApplication: "Archive Utility.app"
    )

    /**
     * 設定を読み込む
     * 1. App Group UserDefaults
     * 2. 既定値（空）
     */
    static func load() -> KeywordSettings {
        if var settings = loadFromSharedDefaults() {
            if settings.migrateApplicationPaths() {
                try? saveToSharedDefaults(settings)
            }
            return settings
        }

        NSLog("ルーティング設定が見つからなかったため、既定値を返します")
        return defaultSettings
    }

    /**
     * アプリ名のみの設定（旧形式）をフルパスに変換する後方互換処理
     */
    @discardableResult
    private mutating func migrateApplicationPaths() -> Bool {
        var hasUpdated = false

        for i in rules.indices {
            let app = rules[i].application
            if app != "internal" && !app.hasPrefix("/") {
                if let url = ApplicationResolver.resolveApplicationURL(from: app) {
                    rules[i].application = url.path
                    hasUpdated = true
                }
            }
        }

        if defaultApplication != "internal" && !defaultApplication.hasPrefix("/") && !defaultApplication.isEmpty {
            if let url = ApplicationResolver.resolveApplicationURL(from: defaultApplication) {
                defaultApplication = url.path
                hasUpdated = true
            }
        }

        return hasUpdated
    }

    /**
     * 設定を App Group UserDefaults に保存
     */
    func save() throws {
        try Self.saveToSharedDefaults(self)
        NSLog("ルーティング設定を保存しました（UserDefaults）")
    }

    /**
     * 初回起動時にサンプル設定を投入（空設定時のみ）
     */
    static func seedDefaultSettingsIfNeeded() {
        let settings = load()
        if settings.rules.isEmpty && settings.defaultApplication.isEmpty {
            do {
                try sampleSettings.save()
                NSLog("ルーティング設定のサンプル値を初期投入しました")
            } catch {
                NSLog("ルーティング設定の初期投入に失敗しました: %@", error.localizedDescription)
            }
        }
    }

    private static func saveToSharedDefaults(_ settings: KeywordSettings) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(settings)
        CZSettings.shared.userDefaults.set(data, forKey: CZSettingsKeys.routingSettingsData)
    }

    private static func loadFromSharedDefaults() -> KeywordSettings? {
        let defaults = CZSettings.shared.userDefaults
        guard let data = defaults.data(forKey: CZSettingsKeys.routingSettingsData) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(KeywordSettings.self, from: data)
        } catch {
            NSLog("UserDefaults のルーティング設定デコードに失敗: %@", error.localizedDescription)
            return nil
        }
    }
}
