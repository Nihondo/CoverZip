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
     * @param zipFileURL ZIPファイルのURL（ファイル名取得用、必要に応じて使用）
     * @param originalFileName 元のZIPファイル名（優先的に使用）
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
        
        if let originalFileName = originalFileName {
            // 元のファイル名を使用（拡張子を除去）
            fileName = URL(fileURLWithPath: originalFileName).deletingPathExtension().lastPathComponent
        } else {
            // URLから取得
            fileName = zipFileURL.deletingPathExtension().lastPathComponent
        }
        
        return checkKeyword(for: fileName, using: settings)
    }
    
    /**
     * ファイル名に対してキーワードマッチングを実行（簡素化版）
     * 
     * @param fileName チェック対象のファイル名（拡張子除去済み）
     * @param settings JSON設定ファイルのキーワード設定
     * @return マッチング結果
     */
    static func checkKeyword(for fileName: String, using settings: KeywordSettings) -> KeywordMatchResult {
        NSLog("ZIPファイル名マッチング開始: ファイル名='\(fileName)'")
        
        // 各キーワードをチェック
        for (keyword, keywordItem) in settings.keywords {
            NSLog("キーワードチェック: '\(keyword)' (タイプ: \(keywordItem.type))")
            
            // ファイル名のみのマッチングをサポート（pathのマッチングは無効）
            if keywordItem.type == .filename {
                let isMatch = fileName.lowercased().contains(keyword.lowercased())
                NSLog("ファイル名マッチング: '\(fileName)' vs '\(keyword)' -> \(isMatch)")
                
                if isMatch {
                    NSLog("マッチ成功: '\(keyword)' -> '\(keywordItem.application)'")
                    return KeywordMatchResult(
                        matchedApplication: keywordItem.application,
                        matchedKeywords: [keyword],
                        matchType: .filename
                    )
                }
            }
        }
        
        // マッチなし - デフォルトアプリケーションを返す
        NSLog("マッチなし - デフォルトアプリケーション: '\(settings.default)'")
        return KeywordMatchResult(
            matchedApplication: settings.default.isEmpty ? nil : settings.default,
            matchedKeywords: [],
            matchType: .none
        )
    }
    
}