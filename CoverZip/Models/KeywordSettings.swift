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
enum KeywordType: String, Codable {
    case pathname = "pathname"
    case filename = "filename"
}

/**
 * マッチング方式を表す列挙型
 */
enum MatchMode: String, Codable {
    case contains = "contains"     // 部分一致（デフォルト）
    case wildcard = "wildcard"     // ワイルドカード (*,?)
    case regex = "regex"           // 正規表現
}

/**
 * 個別キーワード設定を表す構造体
 */
struct KeywordItem: Codable {
    let type: KeywordType
    let application: String
    let matchMode: MatchMode
    
    // デフォルト値を提供するイニシャライザ
    init(type: KeywordType, application: String, matchMode: MatchMode = .contains) {
        self.type = type
        self.application = application
        self.matchMode = matchMode
    }
    
    // 後方互換性のためのDecoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(KeywordType.self, forKey: .type)
        application = try container.decode(String.self, forKey: .application)
        matchMode = try container.decodeIfPresent(MatchMode.self, forKey: .matchMode) ?? .contains
    }
    
    private enum CodingKeys: String, CodingKey {
        case type, application, matchMode
    }
}

/**
 * JSON設定ファイルに対応したキーワード設定モデル
 */
struct KeywordSettings: Codable {
    var keywords: [String: KeywordItem]
    var `default`: String
    
    static let defaultSettings = KeywordSettings(
        keywords: [:],
        default: ""
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
     * デフォルト設定ファイルを作成（開発用）
     */
    static func createDefaultSettingsFile() {
        let defaultKeywords: [String: KeywordItem] = [
            "コミック": KeywordItem(type: .filename, application: "SimpleComicViewer.app", matchMode: .contains),
            "manga": KeywordItem(type: .filename, application: "SimpleComicViewer.app", matchMode: .contains),
            "comic": KeywordItem(type: .pathname, application: "SimpleComicViewer.app", matchMode: .contains),
            "vol*": KeywordItem(type: .filename, application: "SimpleComicViewer.app", matchMode: .wildcard),
            "^backup_\\d+$": KeywordItem(type: .pathname, application: "Archive Utility.app", matchMode: .regex),
            "写真": KeywordItem(type: .filename, application: "Photos.app", matchMode: .contains),
            "photo": KeywordItem(type: .pathname, application: "Photos.app", matchMode: .contains)
        ]
        
        let settings = KeywordSettings(
            keywords: defaultKeywords,
            default: "Archive Utility.app"
        )
        
        guard let appSupportURL = getApplicationSupportDirectory() else { return }
        let settingsURL = appSupportURL.appendingPathComponent("settings.json")
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        if let data = try? encoder.encode(settings) {
            try? data.write(to: settingsURL)
            NSLog("Default settings file created at: %@", settingsURL.path)
        }
    }
    
}

