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
        case fileExtension
        case none
    }
}

/**
 * キーワードマッチング処理を担当するクラス
 * ファイル名とパス名に対するキーワードマッチングを実行
 */
class KeywordMatcher {
    /**
     * アーカイブファイルURLに対してキーワードマッチングを実行
     *
     * @param zipFileURL チェック対象のアーカイブファイルURL
     * @param settings ルーティング設定
     * @return マッチング結果
     */
    static func checkKeyword(for zipFileURL: URL, using settings: KeywordSettings) -> KeywordMatchResult {
        let fileName = zipFileURL.deletingPathExtension().lastPathComponent
        let folderComponents = zipFileURL.deletingLastPathComponent().pathComponents.filter { $0 != "/" }
        let fileExtension = zipFileURL.pathExtension
        return checkKeyword(for: fileName, folderComponents: folderComponents, fileExtension: fileExtension, using: settings)
    }
    
    /**
     * ファイル名とパス名に対してキーワードマッチングを実行（完全版）
     *
     * @param fileName チェック対象のファイル名（拡張子除去済み）
     * @param fullPath チェック対象のフルパス
     * @param settings ルーティング設定
     * @return マッチング結果
     */
    static func checkKeyword(for fileName: String, folderComponents: [String], fileExtension: String, using settings: KeywordSettings) -> KeywordMatchResult {
        #if DEBUG
        let folderDesc = folderComponents.joined(separator: "/")
        NSLog("アーカイブファイルマッチング開始: ファイル名='\(fileName)', フォルダ='\(folderDesc)', 拡張子='\(fileExtension)'")
        #endif

        for rule in settings.rules {
            #if DEBUG
            NSLog("ルールチェック: '\(rule.keyword)' (タイプ: \(rule.type))")
            #endif

            let isMatch: Bool
            let matchType: KeywordMatchResult.MatchType

            switch rule.type {
            case .filename:
                matchType = .filename
                isMatch = performMatch(fileName, keyword: rule.keyword, mode: rule.matchMode)

            case .fileExtension:
                matchType = .fileExtension
                isMatch = performMatch(fileExtension, keyword: rule.keyword, mode: rule.matchMode)

            case .pathname:
                matchType = .pathname
                isMatch = folderComponents.reversed().contains { folder in
                    performMatch(folder, keyword: rule.keyword, mode: rule.matchMode)
                }
            }

            #if DEBUG
            switch rule.type {
            case .filename:
                NSLog("ファイル名マッチング (\(rule.matchMode)): '\(fileName)' vs '\(rule.keyword)' -> \(isMatch)")
            case .fileExtension:
                NSLog("拡張子マッチング (\(rule.matchMode)): '\(fileExtension)' vs '\(rule.keyword)' -> \(isMatch)")
            case .pathname:
                NSLog("フォルダ名マッチング (\(rule.matchMode)): vs '\(rule.keyword)' -> \(isMatch)")
            }
            #endif

            if isMatch {
                #if DEBUG
                NSLog("マッチ成功: '\(rule.keyword)' -> '\(rule.application)' (タイプ: \(matchType))")
                #endif
                return KeywordMatchResult(
                    matchedApplication: rule.application,
                    matchedKeywords: [rule.keyword],
                    matchType: matchType
                )
            }
        }

        #if DEBUG
        NSLog("マッチなし - デフォルトアプリケーション: '\(settings.defaultApplication)'")
        #endif
        return KeywordMatchResult(
            matchedApplication: settings.defaultApplication.isEmpty ? nil : settings.defaultApplication,
            matchedKeywords: [],
            matchType: .none
        )
    }
    
    // MARK: - マッチング機能
    
    /**
     * 統合マッチング関数 - マッチング方式に応じて適切な処理を実行
     */
    private static func performMatch(_ text: String, keyword: String, mode: MatchMode) -> Bool {
        switch mode {
        case .contains:
            return text.lowercased().contains(keyword.lowercased())
            
        case .startsWith:
            return text.lowercased().hasPrefix(keyword.lowercased())
            
        case .endsWith:
            return text.lowercased().hasSuffix(keyword.lowercased())
            
        case .wildcard:
            return matchesWildcard(text, pattern: keyword)
            
        case .regex:
            return matchesRegex(text, pattern: keyword)
        }
    }
    
    /**
     * ワイルドカードマッチング (*,? をサポート)
     */
    private static func matchesWildcard(_ text: String, pattern: String) -> Bool {
        // ワイルドカードを正規表現に変換
        let regexPattern = pattern
            .replacingOccurrences(of: "\\", with: "\\\\")  // バックスラッシュをエスケープ
            .replacingOccurrences(of: ".", with: "\\.")    // ドットをエスケープ
            .replacingOccurrences(of: "^", with: "\\^")    // ハットをエスケープ
            .replacingOccurrences(of: "$", with: "\\$")    // ドルをエスケープ
            .replacingOccurrences(of: "*", with: ".*")     // * を .* に変換
            .replacingOccurrences(of: "?", with: ".")      // ? を . に変換
        
        return text.range(of: "^" + regexPattern + "$", options: [.regularExpression, .caseInsensitive]) != nil
    }
    
    /**
     * 正規表現マッチング
     */
    private static func matchesRegex(_ text: String, pattern: String) -> Bool {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        } catch {
            NSLog("正規表現エラー: '\(pattern)' - \(error.localizedDescription)")
            // 正規表現が無効な場合は通常の部分一致にフォールバック
            return text.lowercased().contains(pattern.lowercased())
        }
    }
    
}
