//
//  NaturalSort.swift
//  Shared utilities for natural filename sorting
//

import Foundation

public enum NaturalSort {
    /// Compare two filenames in a natural order where digit runs are compared numerically.
    /// Case-insensitive; ties break by digit length, then token count, then localized compare.
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
