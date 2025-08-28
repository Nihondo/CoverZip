//
//  FileMenuCommands.swift
//  CoverZip
//
//  ファイルメニューに「ZIPを開く…」を追加
//

import SwiftUI

struct FileMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("ZIPを開く…") {
                FileOpenPanelService.presentAndOpenZip()
            }
            .keyboardShortcut("o", modifiers: [.command])
        }
    }
}
