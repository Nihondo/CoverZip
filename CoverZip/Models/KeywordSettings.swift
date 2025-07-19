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
 * 個別キーワード設定を表す構造体
 */
struct KeywordItem: Codable {
    let type: KeywordType
    let application: String
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
     * 設定のキャッシュを無効化して強制再読み込みするためのフラグ
     */
    private static var forceReloadFlag = false
    
    /**
     * アプリケーションバンドル内のsettings.jsonファイルから設定を読み込む
     */
    static func load() -> KeywordSettings {
        // 1. アプリケーションバンドル内のsettings.jsonを試す
        if let bundlePath = Bundle.main.path(forResource: "settings", ofType: "json"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: bundlePath)),
           let settings = try? JSONDecoder().decode(KeywordSettings.self, from: data) {
            return settings
        }
        
        // 2. アプリケーションサポートディレクトリのsettings.jsonを試す
        if let appSupportURL = getApplicationSupportDirectory(),
           let data = try? Data(contentsOf: appSupportURL.appendingPathComponent("settings.json")),
           let settings = try? JSONDecoder().decode(KeywordSettings.self, from: data) {
            return settings
        }
        
        // 3. デフォルト設定を返す
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
     * 設定をアプリケーションサポートディレクトリに保存
     */
    func save() {
        guard let appSupportURL = Self.getApplicationSupportDirectory() else { return }
        
        let settingsURL = appSupportURL.appendingPathComponent("settings.json")
        
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: settingsURL)
        }
    }
    
    /**
     * デフォルト設定ファイルを作成（開発用）
     */
    static func createDefaultSettingsFile() {
        let defaultKeywords: [String: KeywordItem] = [
            "コミック": KeywordItem(type: .filename, application: "SimpleComicViewer.app"),
            "manga": KeywordItem(type: .filename, application: "SimpleComicViewer.app"),
            "comic": KeywordItem(type: .pathname, application: "SimpleComicViewer.app"),
            "写真": KeywordItem(type: .filename, application: "Photos.app"),
            "photo": KeywordItem(type: .pathname, application: "Photos.app")
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
            print("Default settings file created at: \(settingsURL.path)")
        }
    }
    
    /**
     * 設定の強制再読み込みを実行
     * 外部エディタで変更された設定を反映するために使用
     */
    static func forceReload() {
        forceReloadFlag = true
        NSLog("設定の強制再読み込みフラグを設定しました")
    }
}

/**
 * 旧形式との互換性を保つためのマネージャークラス（簡素化版）
 */
class KeywordSettingsManager: ObservableObject {
    @Published var settings: KeywordSettings
    
    init() {
        self.settings = KeywordSettings.load()
    }
    
    func setDefaultApplication(_ application: String) {
        settings.default = application
        settings.save()
    }
}