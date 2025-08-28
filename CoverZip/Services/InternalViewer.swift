//
//  InternalViewer.swift
//  CoverZip
//
//  内蔵ビューアとしてQuick Lookパネルを用いてZIPを表示する薄いラッパー
//

import AppKit
import QuickLook
import QuickLookUI

final class InternalViewer: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = InternalViewer()

    private var currentURL: URL?

    // 公開API: 内蔵ビューアでZIPを表示
    func show(url: URL) {
        currentURL = url

        // アプリを前面に
        NSApp.activate(ignoringOtherApps: true)

        guard let panel = QLPreviewPanel.shared() else {
            // まれにnilの場合があるため安全にフォールバック
            if let url = currentURL {
                _ = NSWorkspace.shared.open(url)
            }
            return
        }

        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    // MARK: - QLPreviewPanelDataSource
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return currentURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        // NSURLはQLPreviewItemに準拠
        return currentURL as NSURL?
    }

    // MARK: - QLPreviewPanelDelegate (必要に応じて拡張)
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        // ここで独自のキーハンドリング等を行いたい場合に拡張
        return false
    }
}
