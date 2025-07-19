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
        guard let data = configuration.file.regularFileContents,
              let fileURL = data.dataToTemporaryFile() else {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        // 元のファイル名を取得
        let originalFileName = configuration.file.filename ?? "unknown.zip"
        
        self.zipFileURL = fileURL
        self.originalFileName = originalFileName
        let fileInfos = ZipAnalyzer.analyzeZipContents(at: fileURL)
        let settings = KeywordSettings.load()
        let matchResult = KeywordMatcher.findMatchingApplication(for: fileURL, originalFileName: originalFileName, using: settings)
        
        self.fileInfos = fileInfos
        self.matchResult = matchResult
        
        if let application = matchResult.matchedApplication {
            self.launchResult = AppLauncher.launchApplication(with: fileURL, applicationName: application)
        } else {
            self.launchResult = AppLauncher.launchWithDefaultApplication(zipFileURL: fileURL)
        }
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // ZIP ファイルは読み取り専用として扱う
        if let url = zipFileURL,
           let data = try? Data(contentsOf: url) {
            return .init(regularFileWithContents: data)
        }
        throw CocoaError(.fileWriteUnknown)
    }
    
}

/**
 * Data を一時ファイルに保存するための拡張
 */
extension Data {
    func dataToTemporaryFile() -> URL? {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("zip")
        
        do {
            try self.write(to: tempURL)
            return tempURL
        } catch {
            return nil
        }
    }
}
