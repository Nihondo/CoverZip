//
//  ViewMenuCommands.swift
//  CoverZip
//
//  メニューバー「表示」メニューの定義。右クリックメニューと同じ InternalViewer のアクションに合流する。
//

import AppKit
import Combine
import SwiftUI

// MARK: - ViewMenuState

/// メニューバー「表示」メニューの状態を管理する ObservableObject。
/// CZDistributedNotifications.settingsChanged を購読し、InternalViewer の
/// セッション状態と常に同期される。
final class ViewMenuState: ObservableObject {
    static let shared = ViewMenuState()

    @Published var isRightToLeftReading: Bool = true
    @Published var currentViewMode: ViewModePreference = .auto
    @Published var spreadPairOffset: Int = 0
    @Published var isTransitionEnabled: Bool = true
    @Published var isSlideshowEnabled: Bool = false
    @Published var isThumbnailStripVisible: Bool = true
    @Published var isViewerOpen: Bool = false

    private var settingsObserver: NSObjectProtocol?
    private var windowStateObserver: NSObjectProtocol?

    private init() {
        syncFromSettings()
        isViewerOpen = QLPreviewInputDriver.hasOpenViewerWindow
        settingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: CZDistributedNotifications.settingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncFromSettings()
        }
        windowStateObserver = NotificationCenter.default.addObserver(
            forName: QLPreviewInputDriver.viewerWindowStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isViewerOpen = QLPreviewInputDriver.hasOpenViewerWindow
        }
    }

    private func syncFromSettings() {
        let state = PreviewSessionStateStore.loadState(resetSlideshowState: false)
        isRightToLeftReading = state.isRightToLeftReading
        currentViewMode = state.currentViewMode
        spreadPairOffset = state.spreadPairOffset
        isTransitionEnabled = state.isTransitionEnabled
        isSlideshowEnabled = state.isSlideshowEnabled
        isThumbnailStripVisible = state.isThumbnailStripVisible
    }

    // MARK: - 操作メソッド（InternalViewer の apply メソッドへ委譲）

    func setRightToLeft() {
        isRightToLeftReading = true
        InternalViewer.shared.applySetRightToLeft()
    }

    func setLeftToRight() {
        isRightToLeftReading = false
        InternalViewer.shared.applySetLeftToRight()
    }

    func setViewModeAuto() {
        currentViewMode = .auto
        InternalViewer.shared.applySetViewModeAuto()
    }

    func setViewModeSingle() {
        currentViewMode = .single
        InternalViewer.shared.applySetViewModeSingle()
    }

    func setViewModeSpread() {
        currentViewMode = .spread
        InternalViewer.shared.applySetViewModeSpread()
    }

    func toggleTransition() {
        isTransitionEnabled.toggle()
        InternalViewer.shared.applyToggleTransition()
    }

    func toggleSlideshow() {
        isSlideshowEnabled.toggle()
        InternalViewer.shared.applyToggleSlideshow()
    }

    func toggleSpreadPairOffset() {
        spreadPairOffset = 1 - spreadPairOffset
        InternalViewer.shared.applyToggleSpreadPairOffset()
    }

    func toggleThumbnailStrip() {
        isThumbnailStripVisible.toggle()
        InternalViewer.shared.applyToggleThumbnailStrip()
    }
}

// MARK: - ViewMenuCommands

struct ViewMenuCommands: Commands {
    @ObservedObject private var state = ViewMenuState.shared

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Group {
                // 読み方向
                Toggle(CZPreviewContextMenuLayout.title(for: .setRightToLeftReading), isOn: Binding(
                    get: { state.isRightToLeftReading },
                    set: { if $0 { state.setRightToLeft() } }
                ))

                Toggle(CZPreviewContextMenuLayout.title(for: .setLeftToRightReading), isOn: Binding(
                    get: { !state.isRightToLeftReading },
                    set: { if $0 { state.setLeftToRight() } }
                ))

                Divider()

                // 表示モード
                Toggle(CZPreviewContextMenuLayout.title(for: .setViewModeAuto), isOn: Binding(
                    get: { state.currentViewMode == .auto },
                    set: { if $0 { state.setViewModeAuto() } }
                ))
                .keyboardShortcut("0")

                Toggle(CZPreviewContextMenuLayout.title(for: .setViewModeSingle), isOn: Binding(
                    get: { state.currentViewMode == .single },
                    set: { if $0 { state.setViewModeSingle() } }
                ))
                .keyboardShortcut("1")

                Toggle(CZPreviewContextMenuLayout.title(for: .setViewModeSpread), isOn: Binding(
                    get: { state.currentViewMode == .spread },
                    set: { if $0 { state.setViewModeSpread() } }
                ))
                .keyboardShortcut("2")

                Divider()

                // 補助設定
                Toggle(CZPreviewContextMenuLayout.title(for: .setSpreadPairOffset), isOn: Binding(
                    get: { state.spreadPairOffset == 1 },
                    set: { _ in state.toggleSpreadPairOffset() }
                ))
                .keyboardShortcut("t", modifiers: [.command])

                Toggle(CZPreviewContextMenuLayout.title(for: .setThumbnailStripVisible), isOn: Binding(
                    get: { state.isThumbnailStripVisible },
                    set: { _ in state.toggleThumbnailStrip() }
                ))
                .keyboardShortcut("l")

                Divider()

                // ページ送り / スライドショー
                Toggle(CZPreviewContextMenuLayout.title(for: .setPageTransitionEnabled), isOn: Binding(
                    get: { state.isTransitionEnabled },
                    set: { _ in state.toggleTransition() }
                ))

                Toggle(CZPreviewContextMenuLayout.title(for: .setSlideshowEnabled), isOn: Binding(
                    get: { state.isSlideshowEnabled },
                    set: { _ in state.toggleSlideshow() }
                ))
                .keyboardShortcut("s")
            }
            .disabled(!state.isViewerOpen)
        }
    }
}
