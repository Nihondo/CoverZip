//
//  InternalViewer.swift
//  CoverZip
//
//  内蔵ビューアとしてQuick Lookパネルを用いてZIPを表示する薄いラッパー
//

import AppKit
import Foundation

final class InternalViewer: NSObject {
    static let shared = InternalViewer()
    private var isRightToLeftReading = true
    private var currentViewMode: ViewModePreference = .auto
    private var spreadPairOffset = 0
    private var isTransitionEnabled = true
    private var isSlideshowEnabled = false
    private var isThumbnailStripVisible = true
    private var settingsObserver: NSObjectProtocol?

    // 公開API: 内蔵ビューアでZIPを表示（QLPreviewInputDriver に委譲）
    func show(url: URL) {
        syncSessionStateFromSharedDefaults(resetSlideshowState: true)
        setupSettingsObserverIfNeeded()

        // アプリを前面に
        NSApp.activate(ignoringOtherApps: true)
        // 右クリックのメニューをアプリ側から供給
        QLPreviewInputDriver.contextMenuProvider = { [weak self] in
            guard let self else { return NSMenu() }
            return self.makeContextMenu()
        }
        // 正式経路: 入力ドライバの単体ウィンドウを開く
        QLPreviewInputDriver.openQuickLookWindow(url: url)
    }

    func makeContextMenu() -> NSMenu {
        CZPreviewContextMenuFactory.makeMenu(
            target: self,
            selectorForCommand: { [weak self] command in
                self?.selector(for: command)
            },
            stateForCommand: { [weak self] command in
                self?.menuState(for: command) ?? .off
            },
            shortcutForCommand: { command in
                switch command {
                case .setViewModeAuto:
                    return ("0", [.command])
                case .setViewModeSingle:
                    return ("1", [.command])
                case .setViewModeSpread:
                    return ("2", [.command])
                case .setSpreadPairOffset:
                    return ("t", [.command])
                case .setThumbnailStripVisible:
                    return ("l", [.command])
                case .setSlideshowEnabled:
                    return ("s", [.command])
                default:
                    return nil
                }
            }
        )
    }

    // MARK: - アクション（App側）
    @objc func setRightToLeft(_ sender: NSMenuItem) { applySetRightToLeft() }
    @objc func setLeftToRight(_ sender: NSMenuItem) { applySetLeftToRight() }
    @objc func setViewModeAuto(_ sender: NSMenuItem) { applySetViewModeAuto() }
    @objc func setViewModeSingle(_ sender: NSMenuItem) { applySetViewModeSingle() }
    @objc func setViewModeSpread(_ sender: NSMenuItem) { applySetViewModeSpread() }
    @objc func toggleTransition(_ sender: NSMenuItem) { applyToggleTransition() }
    @objc func toggleSlideshow(_ sender: NSMenuItem) { applyToggleSlideshow() }
    @objc func toggleSpreadPairOffset(_ sender: NSMenuItem) { applyToggleSpreadPairOffset() }
    @objc func toggleThumbnailStripVisibility(_ sender: NSMenuItem) { applyToggleThumbnailStrip() }

    // MARK: - 公開アクション実装（SwiftUI からも呼び出し可能）
    func applySetRightToLeft() {
        applyReadingDirection(isRightToLeft: true)
        CZUserDefaults.shared.set(true, forKey: CZSettingsKeys.isRightToLeftReading)
        PreviewSessionCommandDispatcher.postReadingDirectionChanged(isRightToLeft: true)
        PreviewSessionCommandDispatcher.post(command: .setRightToLeftReading)
    }

    func applySetLeftToRight() {
        applyReadingDirection(isRightToLeft: false)
        CZUserDefaults.shared.set(false, forKey: CZSettingsKeys.isRightToLeftReading)
        PreviewSessionCommandDispatcher.postReadingDirectionChanged(isRightToLeft: false)
        PreviewSessionCommandDispatcher.post(command: .setLeftToRightReading)
    }

    func applySetViewModeAuto() {
        applyViewMode(.auto)
        CZUserDefaults.shared.set(ViewModePreference.auto.rawValue, forKey: CZSettingsKeys.defaultViewMode)
        postSettingsChanged()
        PreviewSessionCommandDispatcher.post(command: .setViewModeAuto)
    }

    func applySetViewModeSingle() {
        applyViewMode(.single)
        CZUserDefaults.shared.set(ViewModePreference.single.rawValue, forKey: CZSettingsKeys.defaultViewMode)
        postSettingsChanged()
        PreviewSessionCommandDispatcher.post(command: .setViewModeSingle)
    }

    func applySetViewModeSpread() {
        applyViewMode(.spread)
        CZUserDefaults.shared.set(ViewModePreference.spread.rawValue, forKey: CZSettingsKeys.defaultViewMode)
        postSettingsChanged()
        PreviewSessionCommandDispatcher.post(command: .setViewModeSpread)
    }

    func applyToggleTransition() {
        let next = !isTransitionEnabled
        applyTransitionEnabled(next)
        CZUserDefaults.shared.set(next, forKey: CZSettingsKeys.pageTransitionEnabled)
        postSettingsChanged()
        PreviewSessionCommandDispatcher.post(command: .setPageTransitionEnabled, boolValue: next)
    }

    func applyToggleSlideshow() {
        let next = !isSlideshowEnabled
        NSLog("[InternalViewer] toggleSlideshow next=%d", next ? 1 : 0)
        applySlideshowEnabled(next)
        CZSettings.shared.isSlideshowEnabled = next
        postSettingsChanged()
        PreviewSessionCommandDispatcher.post(command: .setSlideshowEnabled, boolValue: next)
    }

    func applyToggleSpreadPairOffset() {
        let next = 1 - spreadPairOffset
        applySpreadPairOffset(next)
        CZUserDefaults.shared.set(next, forKey: CZSettingsKeys.spreadPairOffset)
        postSettingsChanged()
        PreviewSessionCommandDispatcher.post(command: .setSpreadPairOffset, intValue: next)
    }

    func applyToggleThumbnailStrip() {
        let next = !isThumbnailStripVisible
        applyThumbnailStripVisibility(next)
        CZSettings.shared.isThumbnailStripVisible = next
        postSettingsChanged()
        PreviewSessionCommandDispatcher.post(command: .setThumbnailStripVisible, boolValue: next)
    }

    // MARK: - 非公開

    private func setupSettingsObserverIfNeeded() {
        guard settingsObserver == nil else { return }
        settingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: CZDistributedNotifications.settingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncSessionStateFromSharedDefaults(resetSlideshowState: false)
        }
    }

    private func syncSessionStateFromSharedDefaults(resetSlideshowState: Bool) {
        let state = PreviewSessionStateStore.loadState(resetSlideshowState: resetSlideshowState)
        isRightToLeftReading = state.isRightToLeftReading
        currentViewMode = state.currentViewMode
        spreadPairOffset = state.spreadPairOffset
        isTransitionEnabled = state.isTransitionEnabled
        isSlideshowEnabled = state.isSlideshowEnabled
        isThumbnailStripVisible = state.isThumbnailStripVisible
    }

    private func selector(for command: CZPreviewSessionCommand) -> Selector? {
        switch command {
        case .setRightToLeftReading:
            return #selector(setRightToLeft(_:))
        case .setLeftToRightReading:
            return #selector(setLeftToRight(_:))
        case .setViewModeAuto:
            return #selector(setViewModeAuto(_:))
        case .setViewModeSingle:
            return #selector(setViewModeSingle(_:))
        case .setViewModeSpread:
            return #selector(setViewModeSpread(_:))
        case .setSpreadPairOffset:
            return #selector(toggleSpreadPairOffset(_:))
        case .setThumbnailStripVisible:
            return #selector(toggleThumbnailStripVisibility(_:))
        case .setPageTransitionEnabled:
            return #selector(toggleTransition(_:))
        case .setSlideshowEnabled:
            return #selector(toggleSlideshow(_:))
        case .goToFirstPage, .goToLastPage, .goForwardPage, .goBackwardPage, .goLeftArrowPage, .goRightArrowPage, .jumpRelativePages:
            return nil
        }
    }

    private func menuState(for command: CZPreviewSessionCommand) -> NSControl.StateValue {
        switch command {
        case .setRightToLeftReading:
            return isRightToLeftReading ? .on : .off
        case .setLeftToRightReading:
            return isRightToLeftReading ? .off : .on
        case .setViewModeAuto:
            return currentViewMode == .auto ? .on : .off
        case .setViewModeSingle:
            return currentViewMode == .single ? .on : .off
        case .setViewModeSpread:
            return currentViewMode == .spread ? .on : .off
        case .setSpreadPairOffset:
            return spreadPairOffset == 1 ? .on : .off
        case .setThumbnailStripVisible:
            return isThumbnailStripVisible ? .on : .off
        case .setPageTransitionEnabled:
            return isTransitionEnabled ? .on : .off
        case .setSlideshowEnabled:
            return isSlideshowEnabled ? .on : .off
        case .goToFirstPage, .goToLastPage, .goForwardPage, .goBackwardPage, .goLeftArrowPage, .goRightArrowPage, .jumpRelativePages:
            return .off
        }
    }

    private func applyReadingDirection(isRightToLeft: Bool) {
        isRightToLeftReading = isRightToLeft
    }

    private func applyViewMode(_ mode: ViewModePreference) {
        currentViewMode = mode
    }

    private func applySpreadPairOffset(_ offset: Int) {
        spreadPairOffset = (offset % 2 + 2) % 2
    }

    private func applyTransitionEnabled(_ enabled: Bool) {
        isTransitionEnabled = enabled
    }

    private func applySlideshowEnabled(_ enabled: Bool) {
        isSlideshowEnabled = enabled
    }

    private func applyThumbnailStripVisibility(_ isVisible: Bool) {
        isThumbnailStripVisible = isVisible
    }

    private func postSettingsChanged() {
        PreviewSessionCommandDispatcher.postSettingsChanged()
    }
}
