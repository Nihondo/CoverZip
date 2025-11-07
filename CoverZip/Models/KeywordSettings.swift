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
    case pathname = "pathname"
    case filename = "filename"

    var displayName: String {
        switch self {
        case .pathname: return "パス名"
        case .filename: return "ファイル名"
        }
    }
}

/**
 * マッチング方式を表す列挙型
 */
enum MatchMode: String, Codable, CaseIterable {
    case contains = "contains"     // 部分一致（デフォルト）
    case wildcard = "wildcard"     // ワイルドカード (*,?)
    case regex = "regex"           // 正規表現

    var displayName: String {
        switch self {
        case .contains: return "を含む"
        case .wildcard: return "ワイルドカード"
        case .regex: return "正規表現"
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
 * JSON設定ファイルに対応したキーワード設定モデル（配列ベース）
 */
struct KeywordSettings: Codable {
    var rules: [KeywordRule]
    var defaultApplication: String

    static let defaultSettings = KeywordSettings(
        rules: [],
        defaultApplication: ""
    )

    /**
     * settings.jsonファイルから設定を読み込む
     * ユーザーが編集可能なApplication Supportディレクトリの設定を優先する
     */
    static func load() -> KeywordSettings {
        // 1. アプリケーションサポートディレクトリのsettings.jsonを試す
        if let appSupportURL = getApplicationSupportDirectory(),
           let data = try? Data(contentsOf: appSupportURL.appendingPathComponent("settings.json")),
           let settings = try? JSONDecoder().decode(KeywordSettings.self, from: data) {
            NSLog("ユーザー設定ファイルを読み込みました: \(appSupportURL.appendingPathComponent("settings.json").path)")
            return settings
        }

        // 2. アプリケーションバンドル内のsettings.jsonを試す
        if let bundlePath = Bundle.main.path(forResource: "settings", ofType: "json"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: bundlePath)),
           let settings = try? JSONDecoder().decode(KeywordSettings.self, from: data) {
            NSLog("バンドル内のデフォルト設定ファイルを読み込みました: \(bundlePath)")
            return settings
        }

        // 3. デフォルト設定を返す
        NSLog("有効な設定ファイルが見つからなかったため、デフォルト設定を返します")
        return defaultSettings
    }

    /**
     * 設定をsettings.jsonファイルに保存
     */
    func save() throws {
        guard let appSupportURL = KeywordSettings.getApplicationSupportDirectory() else {
            throw NSError(domain: "KeywordSettings", code: 1, userInfo: [NSLocalizedDescriptionKey: "Application Support directory not found"])
        }

        let settingsURL = appSupportURL.appendingPathComponent("settings.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(self)
        try data.write(to: settingsURL)
        NSLog("設定ファイルを保存しました: \(settingsURL.path)")
    }

    /**
     * アプリケーションサポートディレクトリを取得
     */
    static func getApplicationSupportDirectory() -> URL? {
        let fileManager = FileManager.default

        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let appURL = appSupportURL.appendingPathComponent("CoverZip")

        // ディレクトリが存在しない場合は作成
        if !fileManager.fileExists(atPath: appURL.path) {
            try? fileManager.createDirectory(at: appURL, withIntermediateDirectories: true, attributes: nil)
        }

        return appURL
    }

    /**
     * デフォルト設定ファイルを作成
     */
    static func createDefaultSettingsFile() {
        let defaultRules = [
            KeywordRule(keyword: "コミック", type: .filename, application: "internal", matchMode: .contains),
            KeywordRule(keyword: "manga", type: .filename, application: "internal", matchMode: .contains),
            KeywordRule(keyword: "vol*", type: .filename, application: "internal", matchMode: .wildcard)
        ]

        let settings = KeywordSettings(
            rules: defaultRules,
            defaultApplication: "Archive Utility.app"
        )

        guard let appSupportURL = getApplicationSupportDirectory() else { return }
        let settingsURL = appSupportURL.appendingPathComponent("settings.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let data = try? encoder.encode(settings) {
            try? data.write(to: settingsURL)
            NSLog("Default settings file created at: %@", settingsURL.path)
        }
    }
}

