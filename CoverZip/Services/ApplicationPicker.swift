//
//  ApplicationPicker.swift
//  CoverZip
//
//  アプリケーション選択パネルを表示するヘルパー
//

import AppKit
import Foundation
import UniformTypeIdentifiers

class ApplicationPicker {

    /**
     * アプリケーション選択パネルを表示
     *
     * @param completion 選択されたアプリケーション名（キャンセル時はnil）
     */
    static func pickApplication(completion: @escaping (String?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "アプリケーションを選択"
        panel.message = "ZIPファイルを開くアプリケーションを選択してください"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.level = .modalPanel

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                completion(nil)
                return
            }

            // アプリケーション名を返す（例: "SimpleComicViewer.app"）
            let appName = url.lastPathComponent
            completion(appName)
        }
    }

    /**
     * よく使うアプリケーションのプリセット
     */
    static let commonApplications = [
        "internal",
        "Archive Utility.app",
        "Finder.app"
    ]

    /**
     * アプリケーション名を表示用テキストに変換
     */
    static func displayName(for application: String) -> String {
        if application == "internal" {
            return "内蔵ビューア"
        }
        return application
    }
}
