//
//  main.swift
//  CoverZipKeyHelper
//
//  Finder QuickLook 用のキー入力ヘルパー
//

import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let controller = KeyHelperController()
withExtendedLifetime(controller) {
    app.run()
}
