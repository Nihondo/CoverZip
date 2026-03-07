//
//  NaturalSort.swift
//  ファイル名の自然順ソートに関する共有ユーティリティ
//

import Foundation

public enum NaturalSort {
    /// 2つのファイル名を自然順で比較する（数字の連続は数値として比較）。
    /// 大文字小文字は無視し、同値時は桁数→トークン数→ローカライズ比較の順で判定する。
    public static func lessFilename(_ lhs: String, _ rhs: String) -> Bool {
        return naturalLess(lhs, rhs)
    }

    private enum Token: Equatable { case text(String); case number(Int, length: Int) }

    private static func naturalLess(_ lhs: String, _ rhs: String) -> Bool {
        let lt = tokenize(lhs.lowercased())
        let rt = tokenize(rhs.lowercased())
        let n = min(lt.count, rt.count)
        for i in 0..<n {
            let a = lt[i]
            let b = rt[i]
            switch (a, b) {
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
        return lhs.localizedCompare(rhs) == .orderedAscending
    }

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
