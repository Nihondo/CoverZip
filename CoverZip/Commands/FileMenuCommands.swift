//
//  FileMenuCommands.swift
//  CoverZip
//
//  ファイルメニューに「ファイルを開く」と「内蔵ビューアで開く」を追加
//

import SwiftUI

struct FileMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("ファイルを開く…") {
                FileOpenPanelService.presentAndRouteZip()
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button("内蔵ビューアで開く…") {
                FileOpenPanelService.presentAndOpenZip()
            }
            .keyboardShortcut("o", modifiers: [.command, .option])
        }
    }
}
