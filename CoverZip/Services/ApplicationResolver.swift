//
//  ApplicationResolver.swift
//  CoverZip
//
//  アプリ識別子（internal/絶対パス/Bundle ID/アプリ名）から起動URLを解決する
//

import AppKit
import Foundation

enum ApplicationResolver {

    static func resolveApplicationURL(from applicationIdentifier: String) -> URL? {
        let normalizedIdentifier = applicationIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty else { return nil }
        guard normalizedIdentifier.lowercased() != "internal" else { return nil }

        if let absolutePathURL = resolveAbsolutePath(from: normalizedIdentifier) {
            return absolutePathURL
        }

        if let bundleURL = resolveBundleIdentifier(from: normalizedIdentifier) {
            return bundleURL
        }

        if let nameResolvedURL = resolveByDirectorySearch(from: normalizedIdentifier) {
            return nameResolvedURL
        }
        return nil
    }

    private static func resolveAbsolutePath(from applicationIdentifier: String) -> URL? {
        guard applicationIdentifier.hasPrefix("/") else { return nil }
        let appURL = URL(fileURLWithPath: applicationIdentifier)
        guard FileManager.default.fileExists(atPath: appURL.path) else { return nil }
        return appURL
    }

    private static func resolveBundleIdentifier(from applicationIdentifier: String) -> URL? {
        let hasBundleIdentifierShape = applicationIdentifier.contains(".") && !applicationIdentifier.hasSuffix(".app")
        guard hasBundleIdentifierShape else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: applicationIdentifier)
    }

    private static func resolveByDirectorySearch(from applicationIdentifier: String) -> URL? {
        let candidateNames = applicationNameCandidates(from: applicationIdentifier).map { normalizedApplicationName(from: $0) }
        let searchDirectories = applicationSearchDirectories()

        for candidateName in candidateNames {
            for searchDirectory in searchDirectories {
                let candidateURL = searchDirectory.appendingPathComponent(candidateName)
                if FileManager.default.fileExists(atPath: candidateURL.path) {
                    return candidateURL
                }
            }
        }
        return nil
    }

    private static func applicationNameCandidates(from applicationIdentifier: String) -> [String] {
        let normalizedName = normalizedApplicationName(from: applicationIdentifier)
        if normalizedName == applicationIdentifier {
            return [applicationIdentifier]
        }
        return [applicationIdentifier, normalizedName]
    }

    private static func normalizedApplicationName(from applicationIdentifier: String) -> String {
        applicationIdentifier.hasSuffix(".app") ? applicationIdentifier : "\(applicationIdentifier).app"
    }

    private static func applicationSearchDirectories() -> [URL] {
        var searchDirectories: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
        ]

        if let userApplicationsURL = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first {
            searchDirectories.append(userApplicationsURL)
        }
        return searchDirectories
    }
}
