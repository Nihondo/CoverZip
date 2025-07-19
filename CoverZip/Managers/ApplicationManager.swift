//
//  ApplicationManager.swift
//  CoverZip
//
//  Created by Nihondo on 2025/07/19.
//

import Foundation
import AppKit

/**
 * システム上のアプリケーションを表す構造体
 */
struct ApplicationItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let bundleIdentifier: String?
    let url: URL
    
    var displayName: String {
        name.replacingOccurrences(of: ".app", with: "")
    }
}

/**
 * システムアプリケーションの検索と管理を担当するクラス
 */
class ApplicationManager: ObservableObject {
    @Published var availableApplications: [ApplicationItem] = []
    @Published var isLoading = false
    
    /**
     * システム上のアプリケーション一覧を取得する
     */
    func loadApplications() {
        isLoading = true
        
        DispatchQueue.global(qos: .background).async {
            let applications = self.findApplications()
            
            DispatchQueue.main.async {
                self.availableApplications = applications.sorted { $0.displayName < $1.displayName }
                self.isLoading = false
            }
        }
    }
    
    /**
     * システム上のアプリケーションを検索する
     * 
     * @return 発見されたアプリケーションのリスト
     */
    private func findApplications() -> [ApplicationItem] {
        var applications: [ApplicationItem] = []
        let fileManager = FileManager.default
        
        // 検索対象ディレクトリ
        var searchPaths = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities"
        ]
        
        // ユーザーのApplicationsディレクトリも追加
        let userAppsPaths = fileManager.urls(for: .applicationDirectory, in: .userDomainMask)
        if let userAppsPath = userAppsPaths.first {
            searchPaths.append(userAppsPath.path)
        }
        
        for searchPath in searchPaths {
            if let items = try? fileManager.contentsOfDirectory(atPath: searchPath) {
                for item in items {
                    if item.hasSuffix(".app") {
                        let appURL = URL(fileURLWithPath: searchPath).appendingPathComponent(item)
                        
                        // Bundle Identifierを取得
                        let bundleIdentifier = getBundleIdentifier(for: appURL)
                        
                        applications.append(ApplicationItem(
                            name: item,
                            bundleIdentifier: bundleIdentifier,
                            url: appURL
                        ))
                    }
                }
            }
        }
        
        // 重複を除去（同じBundle Identifierのアプリは1つだけ残す）
        var uniqueApps: [String: ApplicationItem] = [:]
        for app in applications {
            let key = app.bundleIdentifier ?? app.name
            uniqueApps[key] = app
        }
        
        return Array(uniqueApps.values)
    }
    
    /**
     * アプリケーションのBundle Identifierを取得する
     * 
     * @param url アプリケーションのURL
     * @return Bundle Identifier（取得できない場合はnil）
     */
    private func getBundleIdentifier(for url: URL) -> String? {
        guard let bundle = Bundle(url: url) else { return nil }
        return bundle.bundleIdentifier
    }
    
    /**
     * アプリケーション名で検索する
     * 
     * @param searchText 検索テキスト
     * @return 検索結果のアプリケーションリスト
     */
    func searchApplications(searchText: String) -> [ApplicationItem] {
        if searchText.isEmpty {
            return availableApplications
        }
        
        return availableApplications.filter { app in
            app.displayName.localizedCaseInsensitiveContains(searchText) ||
            app.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    /**
     * よく使われるZIP関連アプリケーションのリストを取得
     */
    static func getCommonZipApplications() -> [String] {
        return [
            "Archive Utility",
            "The Unarchiver",
            "BetterZip 5",
            "Keka",
            "WinZip",
            "YemuZip",
            "SimplyRAR"
        ]
    }
    
    /**
     * よく使われるコミック/画像ビューアアプリケーションのリストを取得
     */
    static func getCommonViewerApplications() -> [String] {
        return [
            "Simple Comic",
            "ComicFlow",
            "YACReader",
            "Sequential",
            "Previewer",
            "Photos"
        ]
    }
}