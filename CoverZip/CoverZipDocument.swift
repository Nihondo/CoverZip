//
//  CoverZipDocument.swift
//  CoverZip
//
//  Created by Nihondo on 2025/07/15.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var zipArchive: UTType {
        UTType("public.zip-archive")!
    }
}

struct CoverZipDocument: FileDocument {
    var zipFileURL: URL?
    var originalFileName: String?
    var fileInfos: [ZipFileInfo] = []
    var matchResult: KeywordMatchResult?
    var launchResult: AppLaunchResult?

    init(zipFileURL: URL? = nil, originalFileName: String? = nil) {
        self.zipFileURL = zipFileURL
        self.originalFileName = originalFileName
        self.fileInfos = []
        self.matchResult = nil
        self.launchResult = nil
        
        if let url = zipFileURL {
            let fileInfos = ZipAnalyzer.analyzeZipContents(at: url)
            let settings = KeywordSettings.load()
            let matchResult = KeywordMatcher.findMatchingApplication(for: url, originalFileName: originalFileName, using: settings)
            
            self.fileInfos = fileInfos
            self.matchResult = matchResult
            
            if let application = matchResult.matchedApplication {
                self.launchResult = AppLauncher.launchApplication(with: url, applicationName: application)
            } else {
                self.launchResult = AppLauncher.launchWithDefaultApplication(zipFileURL: url)
            }
        }
    }

    static var readableContentTypes: [UTType] { [.zipArchive] }

    init(configuration: ReadConfiguration) throws {
        // 元のファイル名を取得
        let originalFileName = configuration.file.filename ?? "unknown.zip"
        
        // プロパティを初期化
        self.zipFileURL = nil
        self.originalFileName = originalFileName
        self.fileInfos = []  // ファイル内容の解析は不要
        
        // ファイル名とパス名のみでキーワードマッチングを実行
        let settings = KeywordSettings.load()
        let matchResult = KeywordMatcher.findMatchingApplication(
            for: URL(fileURLWithPath: originalFileName),
            originalFileName: originalFileName,
            using: settings
        )
        
        self.matchResult = matchResult
        
        // 外部アプリケーション起動を即座に実行
        do {
            guard let data = configuration.file.regularFileContents else {
                NSLog("ファイルデータが読み取れませんでした")
                self.launchResult = .fileNotFound
                return
            }
            
            // 一時ファイルを作成
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("zip")
            
            try data.write(to: tempURL)
            
            // 外部アプリケーションで開く
            if let application = matchResult.matchedApplication {
                NSLog("外部アプリケーション起動: \(application)")
                self.launchResult = AppLauncher.launchApplication(with: tempURL, applicationName: application)
            } else {
                NSLog("デフォルトアプリケーション起動")
                self.launchResult = AppLauncher.launchWithDefaultApplication(zipFileURL: tempURL)
            }
            
            // 遅延削除
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                try? FileManager.default.removeItem(at: tempURL)
            }
            
        } catch {
            NSLog("外部アプリケーション起動に失敗: \(error)")
            self.launchResult = .launchFailed(error)
        }
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // ZIP ファイルは読み取り専用として扱う（データの保存は不要）
        return .init(regularFileWithContents: Data())
    }
    
}

