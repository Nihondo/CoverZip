//
//  main.swift
//  CoverZipKeyHelper
//
//  Finder QuickLook 用のキー入力ヘルパー
//

import AppKit

// 同じ Bundle ID のプロセスが既に起動していれば即終了（二重起動抑止）
let helperBundleID = Bundle.main.bundleIdentifier ?? "com.dmng.CoverZip.KeyHelper"
let running = NSRunningApplication.runningApplications(withBundleIdentifier: helperBundleID)
if running.count > 1 || (running.count == 1 && running.first?.processIdentifier != ProcessInfo.processInfo.processIdentifier) {
    NSLog("[CoverZipKeyHelper] Another instance already running, exiting.")
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let controller = KeyHelperController()
withExtendedLifetime(controller) {
    app.run()
}
