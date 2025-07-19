//
//  CoverZipDocument.swift
//  CoverZip
//
//  Created by Nihondo on 2025/07/15.
//

import SwiftUI
import UniformTypeIdentifiers
import Foundation

extension UTType {
    static var zipArchive: UTType {
        UTType("public.zip-archive")!
    }
}

struct CoverZipDocument: FileDocument {

    init() {
        // 何もしない - ウィンドウ表示は不要
    }

    static var readableContentTypes: [UTType] { [.zipArchive] }

    init(configuration: ReadConfiguration) throws {
        // 元のファイル名を取得
        let originalFileName = configuration.file.filename ?? "unknown.zip"
        
        // ファイル名のみでキーワードマッチングを実行
        let settings = KeywordSettings.load()
        
        // 外部アプリケーション起動を即座に実行
        do {
            guard let data = configuration.file.regularFileContents else {
                NSLog("ファイルデータが読み取れませんでした")
                return
            }
            
            // 一時ファイルを作成
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("zip")
            
            try data.write(to: tempURL)
            
            // キーワードマッチングを実行
            let matchResult = KeywordMatcher.findMatchingApplication(
                for: tempURL,
                originalFileName: originalFileName,
                using: settings
            )
            
            // 外部アプリケーションで開く
            if let application = matchResult.matchedApplication {
                NSLog("外部アプリケーション起動: \(application)")
                _ = AppLauncher.launchApplication(with: tempURL, applicationName: application)
            } else {
                NSLog("デフォルトアプリケーション起動")
                _ = AppLauncher.launchWithDefaultApplication(zipFileURL: tempURL)
            }
            
            // 遅延削除
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                try? FileManager.default.removeItem(at: tempURL)
            }
            
        } catch {
            NSLog("外部アプリケーション起動に失敗: \(error)")
        }
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // ZIP ファイルは読み取り専用として扱う（データの保存は不要）
        return .init(regularFileWithContents: Data())
    }
    
}

