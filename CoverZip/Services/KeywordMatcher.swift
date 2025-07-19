//
//  KeywordMatcher.swift
//  CoverZip
//
//  Created by Nihondo on 2025/07/19.
//

import Foundation

/**
 * キーワードマッチング結果を表す構造体
 */
struct KeywordMatchResult {
    let matchedApplication: String?
    let matchedKeywords: [String]
    let matchType: MatchType
    
    enum MatchType {
        case filename
        case pathname
        case none
    }
}

/**
 * キーワードマッチング処理を担当するクラス
 * ファイル名とパス名に対するキーワードマッチングを実行
 */
class KeywordMatcher {
    
    /**
     * ZIPファイル名に対してキーワードマッチングを実行
     * 
     * @param zipFileURL ZIPファイルのURL（一時ファイルの可能性あり）
     * @param originalFileName 元のZIPファイル名
     * @param settings JSON設定ファイルのキーワード設定
     * @return マッチング結果
     */
    static func findMatchingApplication(
        for zipFileURL: URL,
        originalFileName: String?,
        using settings: KeywordSettings
    ) -> KeywordMatchResult {
        
        // 元のファイル名が指定されている場合はそれを使用、そうでなければURLから取得
        let fileName: String
        let directoryPath: String
        let fullPath: String
        
        if let originalFileName = originalFileName {
            // 元のファイル名を使用（拡張子を除去）
            fileName = URL(fileURLWithPath: originalFileName).deletingPathExtension().lastPathComponent
            directoryPath = zipFileURL.deletingLastPathComponent().path
            fullPath = zipFileURL.deletingLastPathComponent().appendingPathComponent(originalFileName).path
        } else {
            // URLから取得
            fileName = zipFileURL.deletingPathExtension().lastPathComponent
            directoryPath = zipFileURL.deletingLastPathComponent().path
            fullPath = zipFileURL.path
        }
        
        NSLog("ZIPファイル名マッチング開始: ファイル名='\(fileName)', パス='\(directoryPath)'")
        
        // 各キーワードをチェック
        for (keyword, keywordItem) in settings.keywords {
            if let matchResult = checkKeywordForZipFile(
                keyword: keyword,
                keywordItem: keywordItem,
                fileName: fileName,
                directoryPath: directoryPath,
                fullPath: fullPath
            ) {
                return matchResult
            }
        }
        
        // マッチなし - デフォルトアプリケーションを返す
        return KeywordMatchResult(
            matchedApplication: settings.default.isEmpty ? nil : settings.default,
            matchedKeywords: [],
            matchType: .none
        )
    }
    
    /**
     * ZIPファイル自体のファイル名とパスに対するキーワードマッチングをチェック
     * 
     * @param keyword チェック対象のキーワード
     * @param keywordItem キーワード設定項目
     * @param fileName ZIPファイル名（拡張子なし）
     * @param directoryPath ZIPファイルのディレクトリパス
     * @param fullPath ZIPファイルのフルパス
     * @return マッチング結果（マッチしない場合はnil）
     */
    private static func checkKeywordForZipFile(
        keyword: String,
        keywordItem: KeywordItem,
        fileName: String,
        directoryPath: String,
        fullPath: String
    ) -> KeywordMatchResult? {
        
        NSLog("キーワードチェック開始: '\(keyword)' (タイプ: \(keywordItem.type))")
        
        let isMatch: Bool
        let matchType: KeywordMatchResult.MatchType
        
        switch keywordItem.type {
        case .filename:
            NSLog("ZIPファイル名チェック: '\(fileName)' vs キーワード '\(keyword)'")
            isMatch = fileName.lowercased().contains(keyword.lowercased())
            if isMatch {
                NSLog("ZIPファイル名マッチ: '\(fileName)'")
            }
            matchType = .filename
            
        case .pathname:
            NSLog("ZIPパスチェック: '\(fullPath)' vs キーワード '\(keyword)'")
            isMatch = directoryPath.lowercased().contains(keyword.lowercased()) ||
                     fullPath.lowercased().contains(keyword.lowercased())
            if isMatch {
                NSLog("ZIPパスマッチ: '\(fullPath)'")
            }
            matchType = .pathname
        }
        
        if isMatch {
            return KeywordMatchResult(
                matchedApplication: keywordItem.application,
                matchedKeywords: [keyword],
                matchType: matchType
            )
        }
        
        return nil
    }
    
    /**
     * マッチング結果の詳細情報を取得（ZIPファイル名用）
     * 
     * @param zipFileName ZIPファイル名
     * @param zipPath ZIPファイルパス
     * @param keyword マッチしたキーワード
     * @param matchType マッチタイプ
     * @return マッチした場合はtrue
     */
    static func isMatchForZipFile(
        fileName: String,
        path: String,
        keyword: String,
        matchType: KeywordMatchResult.MatchType
    ) -> Bool {
        
        switch matchType {
        case .filename:
            return fileName.lowercased().contains(keyword.lowercased())
        case .pathname:
            return path.lowercased().contains(keyword.lowercased())
        case .none:
            return false
        }
    }
}