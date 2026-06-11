//
//  NaturalSort.swift
//  ファイル名の自然順ソートに関する共有ユーティリティ
//

import Foundation

public enum NaturalSort {
    /// 2つのファイル名を自然順で比較する（数字の連続は数値として比較）。
    /// 大文字小文字は無視し、同値時は桁数→トークン数→ローカライズ比較の順で判定する。
    public static func lessFilename(_ lhs: String, _ rhs: String) -> Bool {
        return NaturalSortKey(lhs) < NaturalSortKey(rhs)
    }

    /// 自然順ソート用に事前計算したキー。
    /// `tokenize(lowercased())` の結果と元文字列を保持し、
    /// ソートのたびに再トークン化することなく `lessFilename` と同じ順序規則で比較できる。
    public struct NaturalSortKey: Comparable {
        private let tokens: [Token]
        private let original: String

        public init(_ s: String) {
            self.original = s
            self.tokens = NaturalSort.tokenize(s.lowercased())
        }

        public static func < (lhs: NaturalSortKey, rhs: NaturalSortKey) -> Bool {
            let lt = lhs.tokens
            let rt = rhs.tokens
            let n = min(lt.count, rt.count)
            for i in 0..<n {
                switch (lt[i], rt[i]) {
                case let (.number(x, lx), .number(y, ly)):
                    if x != y { return x < y }
                    if lx != ly { return lx < ly }
                case let (.text(x), .text(y)):
                    if x != y { return x < y }
                case (.number, .text):
                    return true
                case (.text, .number):
                    return false
                }
            }
            if lt.count != rt.count { return lt.count < rt.count }
            return lhs.original.localizedCompare(rhs.original) == .orderedAscending
        }

        public static func == (lhs: NaturalSortKey, rhs: NaturalSortKey) -> Bool {
            return !(lhs < rhs) && !(rhs < lhs)
        }
    }

    private enum Token: Equatable { case text(String); case number(Int, length: Int) }

    private static func tokenize(_ s: String) -> [Token] {
        var tokens: [Token] = []
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch.isNumber {
                var j = i
                while j < s.endIndex, s[j].isNumber { j = s.index(after: j) }
                let substr = String(s[i..<j])
                let val = Int(substr) ?? 0
                tokens.append(.number(val, length: substr.count))
                i = j
            } else {
                var j = i
                while j < s.endIndex, !s[j].isNumber { j = s.index(after: j) }
                let substr = String(s[i..<j])
                tokens.append(.text(substr))
                i = j
            }
        }
        return tokens
    }
}
