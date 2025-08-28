//
//  FileOpenPanelService.swift
//  CoverZip
//
//  NSOpenPanel から ZIP を選んで起動ルーティングを行う
//

import AppKit
import Foundation
import UniformTypeIdentifiers

enum FileOpenPanelService {
    static func presentAndOpenZip() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [UTType.zip]
        } else {
            panel.allowedFileTypes = ["zip"]
        }
        panel.level = .modalPanel

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            openZip(at: url)
        }
    }

    static func openZip(at url: URL) {
        // ZIP以外は無視
        guard url.pathExtension.lowercased() == "zip" else { return }

    // メニューからのオープン時は常に内蔵ビューアで表示
    InternalViewer.shared.show(url: url)
    }
}
