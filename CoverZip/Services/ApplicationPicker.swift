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
     * @param completion 選択されたアプリケーションのURL（キャンセル時はnil）
     */
    static func pickApplication(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = CZLocalized.string("app_picker.panel.title", defaultValue: "Select Application")
        panel.message = CZLocalized.string("app_picker.panel.message", defaultValue: "Select an application to open ZIP files")
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
            completion(url)
        }
    }

    /**
     * アプリケーションのローカライズ済み表示名を取得
     * CFBundleDisplayName → CFBundleName → ファイル名の順でフォールバック
     */
    static func displayName(for url: URL) -> String {
        let bundle = Bundle(url: url)
        if let name = bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String { return name }
        if let name = bundle?.infoDictionary?["CFBundleDisplayName"] as? String { return name }
        if let name = bundle?.infoDictionary?["CFBundleName"] as? String { return name }
        return url.deletingPathExtension().lastPathComponent
    }

    /**
     * application文字列（フルパスまたは"internal"）から表示名を返す
     */
    static func displayName(for application: String) -> String {
        if application == "internal" {
            return CZLocalized.string("application.internal_viewer", defaultValue: "Built-in Viewer")
        }
        if application.hasPrefix("/") {
            return displayName(for: URL(fileURLWithPath: application))
        }
        if let url = findURL(for: application) {
            return displayName(for: url)
        }
        return application.hasSuffix(".app")
            ? String(application.dropLast(4))
            : application
    }

    /**
     * アプリケーションのアイコンを取得
     */
    static func icon(for url: URL) -> NSImage {
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /**
     * application文字列（フルパスまたは"internal"）からアイコンを返す
     */
    static func icon(for application: String) -> NSImage? {
        guard application != "internal" else { return nil }
        if application.hasPrefix("/") {
            return icon(for: URL(fileURLWithPath: application))
        }
        // アプリ名のみの場合はURLを検索
        if let url = findURL(for: application) {
            return icon(for: url)
        }
        return nil
    }

    /**
     * アプリ名からフルパスURLを検索
     */
    static func findURL(for appName: String) -> URL? {
        ApplicationResolver.resolveApplicationURL(from: appName)
    }
}
