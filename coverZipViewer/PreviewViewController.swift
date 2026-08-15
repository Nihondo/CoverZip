//
//  PreviewViewController.swift
//  coverZipViewer
//
//  Created by Nihondo on 2025/08/24.
//

import Cocoa
import Quartz
import Foundation
import AppKit
import Compression
import QuartzCore
import os.signpost

// MARK: - プレビュー View Controller

class PreviewViewController: NSViewController, QLPreviewingController {
    
    @IBOutlet weak var imageView: NSImageView!
    @IBOutlet weak var rightImageView: NSImageView!
    @IBOutlet weak var pageLabel: NSTextField!
    @IBOutlet weak var pageSlider: NSSlider!
    
    private var imageManager = ImageManager()
    private var readingHistoryManager = ReadingHistoryManager.shared
    private var currentZipFilename: String = ""
    private var mouseMonitors: [Any] = []
    private var isHandlingPassThroughControlInteraction = false
    private var pendingSingleClick: DispatchWorkItem?
    private var currentImageAspect: CGFloat?
    private var lastKnownSinglePageAspect: CGFloat?
    private var lastKnownLeftPageAspect: CGFloat?
    private var lastKnownRightPageAspect: CGFloat?
    private var whitePagePlaceholderCache: [Int: NSImage] = [:]
    private let defaultWhitePageAspect: CGFloat = 0.70
    private let whitePagePlaceholderHeight: CGFloat = 1000
    /// 低解像度（.low）ティアのフォールバック表示を使用するか（体感検証のため一時停止中。trueで復活）
    private static let isLowQualityFallbackEnabled = false
    private var sliderVisibilityWidthThreshold: CGFloat = 600 // この幅未満では非表示（Finderカラム想定）
    // 日本のコミック向けにページ方向を反転（左=進む、右=戻る、スライダーは左が大きいページ）
    private var isRightToLeftReading: Bool = true
    // 見開き表示用の制約管理
    private var spreadConstraints: [NSLayoutConstraint] = []
    private var originalImageViewConstraints: [NSLayoutConstraint] = []
    
    // スライドショー機能
    private var slideshowTimer: Timer?
    private var isSlideshowEnabled: Bool = false
    // ページ切替トランジション（共有設定でON/OFF）
    private var isTransitionEnabled: Bool = true
    // リサイズ監視のためのオブザーバ
    private var windowObservers: [NSObjectProtocol] = []
    // 分散通知（App→Extension設定同期）用オブザーバ
    private var hasSetupDistributedNotificationObservers = false
    // セッション中にユーザーがウィンドウをリサイズしたか
    private var hasUserResizedWindow: Bool = false
    // 履歴から綴じ方向を復元済みか（既定で上書きしないためのフラグ）
    private var didRestoreRTLFromHistory: Bool = false
    // 履歴から表示モードを復元済みか（既定で上書きしないためのフラグ）
    private var didRestoreViewModeFromHistory: Bool = false
    private var didLogHostWindowInfo: Bool = false
    // 読み込みインジケータ
    private var loadingIndicator: NSProgressIndicator?
    // サムネイルストリップ
    private var thumbnailStripView: ThumbnailStripView?
    private var imageViewBottomToStripConstraint: NSLayoutConstraint?
    private var thumbnailStripHeightConstraint: NSLayoutConstraint?
    private var isThumbnailStripVisible: Bool = true
    private var lastVisibleThumbnailStripHeight: CGFloat = 88
    private var cursorAreaOverlay: PreviewCursorAreaView?
    // 画像に重ねる進捗バー（ページスライダー/ページ数ラベルのオーバーレイ版）
    private var pageProgressBar: PageProgressBarView?
    private var isPagerVisible: Bool = false
    private let pagerHoverBandHeight: CGFloat = 80
    private let previewVisibilitySessionID = UUID().uuidString
    private var previewVisibilityHeartbeatTimer: Timer?

    // マウスホイールスクロール管理
    private var scrollAccumulator: CGFloat = 0.0
    private let scrollThreshold: CGFloat = 10.0 // ページ送りに必要な累積量
    private var lastScrollTime: TimeInterval = 0
    private let scrollCooldownInterval: TimeInterval = 0.1 // 連続スクロール防止間隔
    
    // マウスモニター遅延設定用のプロパティ
    private var mouseMonitorSetupTimer: Timer?
    private var mouseMonitorSetupAttempts = 0
    private let maxMouseMonitorSetupAttempts = 10
    
    // 表示モード
    enum ViewMode {
        case single
        case spread
    }
    private enum SpreadPageSide {
        case left
        case right
    }
    private var currentViewMode: ViewMode = .single
    private var didApplyInitialViewMode = false
    
    // ユーザー設定管理
    private var userPreferredViewMode: ViewModePreference = .auto
    private var isAutoMode: Bool {
        return userPreferredViewMode == .auto
    }
    private let performanceLog = OSLog(subsystem: "com.dmng.CoverZip.coverZipViewer", category: "Performance")
    private var isDisplayCurrentImageInFlight: Bool = false
    private var needsDisplayCurrentImageRetry: Bool = false
    private var isDisplayCurrentImageScheduled: Bool = false
    private var lastDisplayCurrentImageTimestamp: CFTimeInterval = 0
    private var lastDisplayKey: String?
    private var lastPrerenderRefreshKey: String?
    private var lastPrerenderRequestKey: String?
    private var lastPrerenderApplyRetryKey: String?
    private var lastImageFallbackRequestKey: String?
    private var lastTinyFallbackRequestKey: String?
    private let minDisplayCurrentImageInterval: CFTimeInterval = 0.008
    private var skipThumbnailSyncOnce: Bool = false

    
    override var nibName: NSNib.Name? {
        return NSNib.Name("PreviewViewController")
    }

    override func loadView() {
        super.loadView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    // 共有設定（UserDefaults）から設定をロード
    isRightToLeftReading = AppSettings.shared.isRightToLeftReading
    sliderVisibilityWidthThreshold = CGFloat(AppSettings.shared.sliderVisibilityWidthThreshold)
    // ユーザー設定の表示モードを初期ロード
    userPreferredViewMode = AppSettings.shared.defaultViewMode
    // ページ送りアニメの初期状態を共有設定からロード
    isTransitionEnabled = AppSettings.shared.pageTransitionEnabled
    isThumbnailStripVisible = AppSettings.shared.isThumbnailStripVisible
    lastVisibleThumbnailStripHeight = loadThumbnailStripHeight()
    NSLog("[DEBUG] Initial userPreferredViewMode loaded: %@", userPreferredViewMode.rawValue)
        setupUI()
        setupGestureRecognizers()
        // 初期状態ではインジケータは表示しない

        // プリレンダー完了の再描画フックは初回displayCurrentImage（preparePreviewOfFile内）より前に必ず設定する。
        // viewDidAppearで設定すると、表紙のプリレンダーが先に完了した場合に通知が失われ、
        // 白ページ/tiny表示のまま昇格しないことがある
        imageManager.onLayerPrerendered = { [weak self] index in
            guard let self else { return }
            let currentPageIndex = self.imageManager.getCurrentPageNumber() - 1
            guard index == currentPageIndex else { return }
            let displayKey = self.buildCurrentDisplayKey()
            guard self.lastPrerenderRefreshKey != displayKey else { return }
            self.lastPrerenderRefreshKey = displayKey
            self.scheduleDisplayCurrentImageIfNeeded()
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        NSLog("[DEBUG] viewWillAppear called, view.window: %@", view.window?.description ?? "nil")
        setupDistributedNotificationObserversIfNeeded()
        postPreviewVisibilityNotification(CZDistributedNotifications.previewExtensionVisible)
        startPreviewVisibilityHeartbeat()
        
        // マウスイベントモニターを遅延設定
        setupMouseMonitorsWithDelay()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopPreviewVisibilityHeartbeat()
        postPreviewVisibilityNotification(CZDistributedNotifications.previewExtensionHidden)
        
        // 読書履歴を保存（デバウンスせず即座に永続化）
        saveReadingPositionToHistory()
        readingHistoryManager.flush()

        // ユーザーがこのセッションでリサイズした場合のみ最終フレームを保存
        if hasUserResizedWindow { saveWindowFrameIfEnabled() }
        // 通知クリーンアップ
        for o in windowObservers { NotificationCenter.default.removeObserver(o) }
        windowObservers.removeAll()
        teardownDistributedNotificationObservers()
        // マウスモニタークリーンアップ
        cleanupMouseMonitors()
        // スライドショーのクリーンアップ
        stopSlideshow()
        // ローディングインジケータ停止
        hideLoadingIndicator()
    }

    deinit {
        stopPreviewVisibilityHeartbeat()
        postPreviewVisibilityNotification(CZDistributedNotifications.previewExtensionHidden)
        readingHistoryManager.flush()
    }

    private func startPreviewVisibilityHeartbeat() {
        stopPreviewVisibilityHeartbeat()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.postPreviewVisibilityNotification(CZDistributedNotifications.previewExtensionVisible)
        }
        previewVisibilityHeartbeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopPreviewVisibilityHeartbeat() {
        previewVisibilityHeartbeatTimer?.invalidate()
        previewVisibilityHeartbeatTimer = nil
    }

    private func postPreviewVisibilityNotification(_ name: Notification.Name) {
        let userInfo: [String: Any] = [
            CZPreviewVisibilityUserInfoKeys.sessionID: previewVisibilitySessionID,
            CZPreviewVisibilityUserInfoKeys.timestamp: Date().timeIntervalSince1970
        ]
        CZUserDefaults.shared.set(Date().timeIntervalSince1970, forKey: CZSettingsKeys.previewLastVisibilityPostAt)
        CZUserDefaults.shared.set(name.rawValue, forKey: CZSettingsKeys.previewLastVisibilityPostName)
        CZUserDefaults.shared.set(previewVisibilitySessionID, forKey: CZSettingsKeys.previewLastVisibilitySessionID)
        // Darwin 通知: NSDistributedNotificationCenter・App Group が届かない QL sandbox でも動作する
        let darwinName = (name == CZDistributedNotifications.previewExtensionVisible)
            ? CZDarwinNotifications.qlVisible
            : CZDarwinNotifications.qlHidden
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(darwinName as CFString),
            nil, nil, true
        )
        DistributedNotificationCenter.default().postNotificationName(
            name,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }

    // MARK: - マウスモニター管理
    
    /// マウスイベントモニターを設定
    private func setupMouseMonitors() {
        // 既存のモニターをクリーンアップしてから設定
        cleanupMouseMonitors()
        
        // デバッグログ
        NSLog("[DEBUG] Setting up mouse monitors. view.window: %@", view.window?.description ?? "nil")
        
        // マウスイベントをホスト（Finder）へ渡さないためにローカルモニタで吸収（down/up 両方）
        if let down = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] event -> NSEvent? in
            guard let self else { return event }
            self.isHandlingPassThroughControlInteraction = false
            
            // window 状態をより寛容にチェック
            let hasWindow = self.view.window != nil
            verboseLog("[DEBUG] LeftMouseDown: view.window=%@, event.window=%@", 
                  self.view.window?.description ?? "nil", 
                  event.window?.description ?? "nil")
            
            // window が nil でも処理を継続（フォールバック）
            if hasWindow || self.view.superview != nil {
                // 座標変換を試行、失敗した場合はより寛容なフォールバック
                if let p = self.convertEventPointToViewRobust(event) {
                    verboseLog("[DEBUG] Converted point: (%f, %f), bounds: %@", p.x, p.y, NSStringFromRect(self.view.bounds))
                    
                    // 自ビュー領域内の時は吸収（NSControl上は通す）
                    guard self.view.bounds.contains(p) else { 
                        verboseLog("[DEBUG] Point outside bounds, passing event")
                        return event 
                    }
                    
                    // Control-クリックはコンテキストメニューを表示
                    if event.modifierFlags.contains(.control) {
                        let menu = self.makeContextMenu()
                        menu.popUp(positioning: nil, at: p, in: self.view)
                        return nil
                    }
                    
                    // スライダーなどのNSControl（やそのサブビュー）上のクリックは通す（ただしimageView配下は除外）
                    if self.isPointInsidePassThroughControl(p) {
                        self.isHandlingPassThroughControlInteraction = true
                        self.immediatelyJumpSliderIfNeeded(atViewPoint: p)
                        verboseLog("[DEBUG] Mouse down passed through to control")
                        return event
                    }
                    
                    // 画像エリアのクリックは吸収（ダブルクリック抑止）
                    self.pendingSingleClick?.cancel()
                    self.pendingSingleClick = nil
                    verboseLog("[DEBUG] Mouse down absorbed")
                    return nil
                } else {
                    verboseLog("[DEBUG] Coordinate conversion failed, passing event")
                    return event
                }
            }
            verboseLog("[DEBUG] No valid window context, passing event")
            return event
        }) {
            mouseMonitors.append(down)
            NSLog("[DEBUG] Successfully registered leftMouseDown monitor")
        } else {
            NSLog("[ERROR] Failed to register leftMouseDown monitor")
        }
        
        // 右クリックで拡張のメニューを確実に表示（QLPreviewView 埋め込みでも有効化）
        if let rdown = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown, handler: { [weak self] event -> NSEvent? in
            guard let self else { return event }
            
            verboseLog("[DEBUG] RightMouseDown: view.window=%@", self.view.window?.description ?? "nil")
            
            // より寛容な window チェック
            if self.view.window != nil || self.view.superview != nil {
                if let p = self.convertEventPointToViewRobust(event), self.view.bounds.contains(p) {
                    let menu = self.makeContextMenu(includeDebugInfo: event.modifierFlags.contains(.shift))
                    menu.popUp(positioning: nil, at: p, in: self.view)
                    verboseLog("[DEBUG] Context menu displayed")
                    return nil
                }
            }
            return event
        }) {
            mouseMonitors.append(rdown)
            NSLog("[DEBUG] Successfully registered rightMouseDown monitor")
        } else {
            NSLog("[ERROR] Failed to register rightMouseDown monitor")
        }
        
        // マウスホイールスクロールでページ送り
        if let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event -> NSEvent? in
            guard let self else { return event }
            
            // より寛容な window チェック
            if self.view.window != nil || self.view.superview != nil {
                if let p = self.convertEventPointToViewRobust(event) {
                    // 自ビュー領域内のスクロールのみ処理
                    guard self.view.bounds.contains(p) else { return event }
                    
                    // スライダーなどのNSControl（やそのサブビュー）上のスクロールは通す
                    if self.isPointInsidePassThroughControl(p) {
                        return event
                    }
                    
                    // スクロールでページ送り処理を実行
                    if self.handleScrollEvent(event) {
                        verboseLog("[DEBUG] Scroll event handled")
                        return nil // イベントを吸収
                    }
                }
            }
            return event
        }) {
            mouseMonitors.append(scroll)
            NSLog("[DEBUG] Successfully registered scrollWheel monitor")
        } else {
            NSLog("[ERROR] Failed to register scrollWheel monitor")
        }
        
        if let up = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] event -> NSEvent? in
            guard let self else { return event }
            if self.isHandlingPassThroughControlInteraction {
                self.isHandlingPassThroughControlInteraction = false
                verboseLog("[DEBUG] MouseUp treated as pass-through control interaction")
                return event
            }
            
            verboseLog("[DEBUG] LeftMouseUp: view.window=%@", self.view.window?.description ?? "nil")
            
            // より寛容な window チェック
            if self.view.window != nil || self.view.superview != nil {
                if let vPoint = self.convertEventPointToViewRobust(event) {
                    verboseLog("[DEBUG] MouseUp at (%f, %f), bounds: %@", vPoint.x, vPoint.y, NSStringFromRect(self.view.bounds))
                    
                    // 自ビュー領域外はホストに渡す
                    guard self.view.bounds.contains(vPoint) else { 
                        verboseLog("[DEBUG] MouseUp outside bounds, passing event")
                        return event 
                    }
                    
                    // スライダーなどのNSControl上のクリックは通す
                    if self.isPointInsidePassThroughControl(vPoint) { 
                        verboseLog("[DEBUG] MouseUp passed through to control")
                        return event 
                    }
                    
                    // マウスアップでページめくり処理を実行（画像エリアのみ）
                    let bounds = self.view.bounds
                    let isLeftHalf = vPoint.x < bounds.width / 2
                    let isSpreadMode = self.currentViewMode == .spread
                    
                    verboseLog("[DEBUG] Page navigation: isLeftHalf=%d, isSpreadMode=%d, isRTL=%d", 
                          isLeftHalf, isSpreadMode, self.isRightToLeftReading)
                    
                    // スライドショー中の手動操作は一時的に停止・再開
                    let wasSlideshow = self.isSlideshowEnabled
                    if wasSlideshow { self.stopSlideshow() }
                    
                    var navigationHandled = false
                    
                    if self.isRightToLeftReading {
                        // 反転: 左=進む、右=戻る
                        if isLeftHalf {
                            verboseLog("[DEBUG] RTL: Left click - Next page")
                            if self.imageManager.nextImage(isSpreadMode: isSpreadMode) {
                                self.setViewMode(self.shouldUseSpreadMode() ? .spread : .single)
                                self.applyTransition(forward: true)
                                self.displayCurrentImage()
                                self.saveReadingPositionToHistory()
                                navigationHandled = true
                            }
                        } else {
                            verboseLog("[DEBUG] RTL: Right click - Previous page")
                            if self.imageManager.previousImage(isSpreadMode: isSpreadMode) {
                                self.setViewMode(self.shouldUseSpreadMode() ? .spread : .single)
                                self.applyTransition(forward: false)
                                self.displayCurrentImage()
                                self.saveReadingPositionToHistory()
                                navigationHandled = true
                            }
                        }
                    } else {
                        // 通常: 左=戻る、右=進む
                        if isLeftHalf {
                            verboseLog("[DEBUG] LTR: Left click - Previous page")
                            if self.imageManager.previousImage(isSpreadMode: isSpreadMode) {
                                self.setViewMode(self.shouldUseSpreadMode() ? .spread : .single)
                                self.applyTransition(forward: false)
                                self.displayCurrentImage()
                                self.saveReadingPositionToHistory()
                                navigationHandled = true
                            }
                        } else {
                            verboseLog("[DEBUG] LTR: Right click - Next page")
                            if self.imageManager.nextImage(isSpreadMode: isSpreadMode) {
                                self.setViewMode(self.shouldUseSpreadMode() ? .spread : .single)
                                self.applyTransition(forward: true)
                                self.displayCurrentImage()
                                self.saveReadingPositionToHistory()
                                navigationHandled = true
                            }
                        }
                    }
                    
                    verboseLog("[DEBUG] Navigation handled: %d", navigationHandled)
                    
                    // スライドショーが有効だった場合は再開
                    if wasSlideshow { self.startSlideshow() }
                    return nil // ホストには渡さない
                } else {
                    verboseLog("[DEBUG] MouseUp coordinate conversion failed, passing event")
                    return event
                }
            }
            verboseLog("[DEBUG] MouseUp no valid window context, passing event")
            return event
        }) {
            mouseMonitors.append(up)
            NSLog("[DEBUG] Successfully registered leftMouseUp monitor")
        } else {
            NSLog("[ERROR] Failed to register leftMouseUp monitor")
        }
        
        // キーダウンモニタ：左右カーソルキーでページナビゲーション
        // makeFirstResponderが失敗する場合でも確実にキー入力を処理するため、
        // マウスモニタと同じローカルモニタパターンで実装
        if let keyDown = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event -> NSEvent? in
            guard let self else { return event }
            guard self.view.window != nil || self.view.superview != nil else { return event }
            guard let specialKey = event.specialKey else { return event }
            if self.isThumbnailStripFirstResponderActive() {
                return event
            }

            let forward: Bool
            switch specialKey {
            case .leftArrow:
                // 右綴じ: 左→次ページ（番号増加）／左綴じ: 左→前ページ（番号減少）
                forward = self.isRightToLeftReading
            case .rightArrow:
                // 右綴じ: 右→前ページ（番号減少）／左綴じ: 右→次ページ（番号増加）
                forward = !self.isRightToLeftReading
            default:
                return event
            }
            _ = self.performPageNavigation(forward: forward)
            return nil // イベントを消費してFinderへ渡さない
        }) {
            mouseMonitors.append(keyDown)
            NSLog("[DEBUG] Successfully registered keyDown monitor")
        } else {
            NSLog("[ERROR] Failed to register keyDown monitor")
        }

        NSLog("[DEBUG] Mouse monitor setup complete. Total monitors: %d", mouseMonitors.count)
    }
    
    /// マウスイベントモニターをクリーンアップ
    private func cleanupMouseMonitors() {
        NSLog("[DEBUG] Cleaning up mouse monitors. Current count: %d", mouseMonitors.count)
        
        for m in mouseMonitors { NSEvent.removeMonitor(m) }
        mouseMonitors.removeAll()
        
        pendingSingleClick?.cancel()
        pendingSingleClick = nil
        isHandlingPassThroughControlInteraction = false
        
        // 遅延設定タイマーもクリーンアップ
        mouseMonitorSetupTimer?.invalidate()
        mouseMonitorSetupTimer = nil
        mouseMonitorSetupAttempts = 0
        
        NSLog("[DEBUG] Mouse monitor cleanup complete")
    }

    
    /// マウスモニターを遅延設定（window が利用可能になるまで待機）
    private func setupMouseMonitorsWithDelay() {
        // 既存のタイマーをキャンセル
        mouseMonitorSetupTimer?.invalidate()
        mouseMonitorSetupTimer = nil
        mouseMonitorSetupAttempts = 0
        
        NSLog("[DEBUG] Starting delayed mouse monitor setup")
        
        // 即座に試行
        if view.window != nil {
            NSLog("[DEBUG] window available immediately, setting up monitors")
            setupMouseMonitors()
            return
        }
        
        // window が利用可能になるまでポーリング
        mouseMonitorSetupTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            
            self.mouseMonitorSetupAttempts += 1
            NSLog("[DEBUG] Mouse monitor setup attempt %d, view.window: %@", 
                  self.mouseMonitorSetupAttempts, self.view.window?.description ?? "nil")
            
            if self.view.window != nil {
                NSLog("[DEBUG] window became available, setting up monitors")
                timer.invalidate()
                self.mouseMonitorSetupTimer = nil
                self.setupMouseMonitors()
            } else if self.mouseMonitorSetupAttempts >= self.maxMouseMonitorSetupAttempts {
                NSLog("[DEBUG] Max setup attempts reached, proceeding with fallback")
                timer.invalidate()
                self.mouseMonitorSetupTimer = nil
                // フォールバック: window が nil でも設定を試行
                self.setupMouseMonitors()
            }
        }
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        postPreviewVisibilityNotification(CZDistributedNotifications.previewExtensionVisible)
        startPreviewVisibilityHeartbeat()
        // Quick LookではFirst Responderを取得しない
        // レイアウト完了後のサイズで初回画像を再フィット
        // 設定の変更を反映
        let newRTL = AppSettings.shared.isRightToLeftReading
        if !didRestoreRTLFromHistory && newRTL != isRightToLeftReading {
            isRightToLeftReading = newRTL
            thumbnailStripView?.isRightToLeft = isRightToLeftReading
            applySliderLayoutDirection()
            syncSliderToCurrentPage()
        }
        let newThreshold = CGFloat(AppSettings.shared.sliderVisibilityWidthThreshold)
        if newThreshold != sliderVisibilityWidthThreshold { sliderVisibilityWidthThreshold = newThreshold; updateSliderVisibilityForContext() }
        // ページ送りアニメ設定の変更を反映
        let newTransition = AppSettings.shared.pageTransitionEnabled
        if newTransition != isTransitionEnabled { isTransitionEnabled = newTransition }
        
        // デフォルト表示モード設定の変更をチェック
        let newViewMode = AppSettings.shared.defaultViewMode
        if !didRestoreViewModeFromHistory && newViewMode != userPreferredViewMode {
            userPreferredViewMode = newViewMode
            // 設定変更時は表示を即座に更新
            if imageManager.hasImages() { displayCurrentImage() }
        }
        if imageManager.hasImages() {
            applyInitialViewModeIfNeeded()
            displayCurrentImage()
        }
        // ホストにサイズ希望を伝える（可能なら）
        updatePreferredContentSizeIfNeeded()
        // 表示コンテキストに応じてスライダー可視性を更新
        updateSliderVisibilityForContext()
        // 読み込み状態に応じてインジケータを更新
        updateLoadingIndicator()

        NSLog("[DEBUG] Host window class check")
        // リサイズ完了時にサイズを保存
        if let win = view.window {
            if !didLogHostWindowInfo {
                didLogHostWindowInfo = true
                let windowClass = NSStringFromClass(type(of: win))
                let styleMaskValue = UInt64(win.styleMask.rawValue)
                NSLog("[DEBUG] Host window class=%@, styleMaskRaw=%llu, styleMask=%@, isKeyWindow=%d", windowClass, styleMaskValue, String(describing: win.styleMask), win.isKeyWindow ? 1 : 0)
            }
            hasUserResizedWindow = false
            let obs = NotificationCenter.default.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: win, queue: .main) { [weak self] _ in
                self?.hasUserResizedWindow = true
                self?.saveWindowFrameIfEnabled()
            }
            windowObservers.append(obs)
            
            // ウィンドウサイズ変更時の画像リサイズ対応
            let resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: win, queue: .main) { [weak self] _ in
                self?.updateImageManagerDisplaySize()
            }
            windowObservers.append(resizeObserver)
        }
        
        // 初期表示サイズを設定
        updateImageManagerDisplaySize()

        // サムネイルストリップのコールバックを設定
        thumbnailStripView?.onPageSelected = { [weak self] index in
            guard let self else { return }
            self.moveToPageFromThumbnail(index + 1)
        }

        // NSCollectionViewへのFirstResponder設定（ベストエフォート）
        if let strip = thumbnailStripView {
            let success = strip.focusCollectionView()
            NSLog("[DEBUG] makeFirstResponder(collectionView): %d", success ? 1 : 0)
            if !success {
                DispatchQueue.main.async { [weak self] in
                    guard let self, let strip = self.thumbnailStripView else { return }
                    let retrySuccess = strip.focusCollectionView()
                    NSLog("[DEBUG] makeFirstResponder(collectionView) retry: %d", retrySuccess ? 1 : 0)
                }
            }
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        NSLog("[DEBUGRECT] BEFORE view.bounds=%@ view.window.frame=%@ preferredContentSize=%@",
              NSStringFromRect(view.bounds),
              view.window.map { NSStringFromRect($0.frame) } ?? "nil",
              NSStringFromSize(preferredContentSize))
        // 自動リサイズ機能を使用するため、手動でのリサイズ処理は不要
        // レイアウト変化に応じてスライダーの可視性を見直す
        updateSliderVisibilityForContext()
        // ホストが実際に与えている領域を preferredContentSize に反映し、余白（背景）が
        // ホスト側に残らないようにする（ページ送りを待たず、レイアウト変化のたびに追従）
        updatePreferredContentSizeIfNeeded()
        NSLog("[DEBUGRECT] AFTER  view.bounds=%@ view.window.frame=%@ preferredContentSize=%@",
              NSStringFromRect(view.bounds),
              view.window.map { NSStringFromRect($0.frame) } ?? "nil",
              NSStringFromSize(preferredContentSize))
        if let overlay = cursorAreaOverlay {
            view.window?.invalidateCursorRects(for: overlay)
        }
        let didBucketChange = updateImageManagerDisplaySize()
        // 見開きプリレンダーレイヤーはframeを手動管理しているため、レイアウト変化に追従させる
        realignSpreadPrerenderedLayers()
        // アスペクト比変更に応じて表示モードを再評価（自動モードのみ）
        if imageManager.hasImages() {
            if lastPrerenderApplyRetryKey != nil {
                scheduleDisplayCurrentImageIfNeeded()
            }
            if isAutoMode {
                // 自動モード：バケット変更またはモード変更時のみ再描画
                let desiredMode: ViewMode = shouldUseSpreadMode() ? .spread : .single
                let didModeChange = desiredMode != currentViewMode
                if didBucketChange || didModeChange {
                    displayCurrentImage()
                }
            } else {
                // 固定モード：バケット変更時のみ表示更新（モード変更なし）
                if didBucketChange {
                    updateImageDisplayOnly()
                }
            }
        }
    }
    

    /*
    func preparePreviewOfSearchableItem(identifier: String, queryString: String?) async throws {
        // CoreSpotlight 対応時はこのメソッドを実装し、拡張の Info.plist で QLSupportsSearchableItems を YES に設定する。

        // ビューの準備に必要な初期化をここで行う。
        // Quick Look はこの処理が返るまでローディングスピナーを表示する。
    }
    */

    func preparePreviewOfFile(at url: URL) async throws {
        NSLog("[DEBUG] preparePreviewOfFile called for: %@", url.lastPathComponent)

        os_signpost(.begin, log: performanceLog, name: "preparePreviewOfFile")
        defer { os_signpost(.end, log: performanceLog, name: "preparePreviewOfFile") }

        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

        // ファイル切り替え時にマウスモニターをクリーンアップ
        cleanupMouseMonitors()
        
        // 新しいファイルが読み込まれる際にスライドショーをリセット
        stopSlideshow()
        isSlideshowEnabled = false
        
    // ファイル名を保存（履歴管理用）
    currentZipFilename = url.lastPathComponent
        
    // まずはグローバル設定の既定を適用（履歴があれば後で上書き）
    didRestoreRTLFromHistory = false
    isRightToLeftReading = AppSettings.shared.isRightToLeftReading
    // 表示モードも既定から開始（履歴があれば後で上書き）
    didRestoreViewModeFromHistory = false
    userPreferredViewMode = AppSettings.shared.defaultViewMode
    // 新規ファイルごとに初期適用フラグをリセット
    didApplyInitialViewMode = false

        // 初回デコードのバケットサイズを先に確定し、二重デコードを防ぐ
        _ = await MainActor.run {
            updateImageManagerDisplaySize(useScreenFallback: true)
        }

        // ZIPファイルから画像を読み込む
        if imageManager.loadImages(from: url) {
            await MainActor.run {
                // 履歴から前回の読書位置を復元
                restoreReadingPositionFromHistory()

                // 初回表示モードをユーザー設定に基づき適用
                applyInitialViewModeIfNeeded()
                // UI要素を更新（読み方向変更を反映）
                applySliderLayoutDirection()
                syncSliderToCurrentPage()
                displayCurrentImage()
                // 初期ロード時に隣接画像を先読み
                imageManager.preloadAdjacentImages()
                updateSliderLimits()
                // 先頭のみ即表示→全件読み込み中であればインジケータ表示
                updateLoadingIndicator()

                // サムネイルストリップの設定（tinyティアキャッシュをImageManagerと共有）
                thumbnailStripView?.isRightToLeft = isRightToLeftReading
                thumbnailStripView?.thumbnailProvider = imageManager
                thumbnailStripView?.configure(itemCount: imageManager.getImageCount())
                syncThumbnailSelection()

                // マウスモニターを遅延設定（window が確実に利用可能になってから）
                NSLog("[DEBUG] Scheduling delayed mouse monitor setup")
                setupMouseMonitorsWithDelay()
            }
        } else if isDirectory {
            // 画像を1枚も含まないフォルダはシステム標準のフォルダプレビューに委譲する
            throw NSError(
                domain: "com.dmng.CoverZip.coverZipViewer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No images found in folder: \(url.lastPathComponent)"]
            )
        } else {
            // 画像が見つからない場合の処理（ZIP）
            await MainActor.run {
                displayNoImagesMessage()
                // 画像なしの場合でもマウスモニターは遅延設定
                NSLog("[DEBUG] No images found, scheduling delayed mouse monitor setup")
                setupMouseMonitorsWithDelay()
            }
        }
    }

    // MARK: - ローディングインジケータ
    private func ensureLoadingIndicator() {
        guard loadingIndicator == nil else { return }
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        loadingIndicator = spinner
    }

    private func showLoadingIndicator() {
        ensureLoadingIndicator()
        loadingIndicator?.isHidden = false
        loadingIndicator?.startAnimation(nil)
    }

    private func hideLoadingIndicator() {
        loadingIndicator?.stopAnimation(nil)
        loadingIndicator?.isHidden = true
    }

    private func updateLoadingIndicator() {
        // 遅延ロード方式ではローディングインジケータは不要
        hideLoadingIndicator()
    }
    
    // MARK: - UI 設定
    
    private func setupUI() {
        // ImageViewの設定
        imageView?.imageScaling = .scaleProportionallyUpOrDown // 自動リサイズ
        imageView?.imageAlignment = .alignCenter
        imageView?.wantsLayer = true // レイヤーバックド表示で高速化
        
        // 右側ImageViewの設定
        rightImageView?.imageScaling = .scaleProportionallyUpOrDown
        rightImageView?.imageAlignment = .alignCenter
        rightImageView?.wantsLayer = true
        rightImageView?.isHidden = true // 初期は非表示
        
        // ImageViewのフレーム設定を確認
        imageView?.imageFrameStyle = .none
        rightImageView?.imageFrameStyle = .none

        // カーソルオーバーレイをサムネイル領域を除く背景全体に配置
        if let imageView {
            let overlay = PreviewCursorAreaView()
            overlay.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(overlay, positioned: .above, relativeTo: imageView)
            NSLayoutConstraint.activate([
                overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                overlay.topAnchor.constraint(equalTo: view.topAnchor),
                overlay.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
            ])
            cursorAreaOverlay = overlay
        }

        // Auto Layout制約の優先度調整
        setupConstraintPriorities()
        
        // 見開き表示用の制約を設定
        setupViewModeConstraints()
        
        // キーイベントを受け取るためのResponder設定
        view.wantsLayer = true
        
        // 高品質な画像表示のための設定
        if let layer = imageView?.layer {
            layer.contentsGravity = .resizeAspect
            layer.minificationFilter = .linear
            layer.magnificationFilter = .linear
        }
        
        if let layer = rightImageView?.layer {
            layer.contentsGravity = .resizeAspect
            layer.minificationFilter = .linear
            layer.magnificationFilter = .linear
        }

        // スライダーを自動追加（XIB未接続時）
        if pageSlider == nil {
            let slider = NSSlider(value: 1, minValue: 1, maxValue: 1, target: self, action: #selector(pageSliderChanged(_:)))
            slider.isContinuous = true
            slider.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(slider)
            self.pageSlider = slider
            applySliderLayoutDirection()
        } else {
            // XIB接続済みならターゲット設定のみ
            pageSlider.target = self
            pageSlider.action = #selector(pageSliderChanged(_:))
            pageSlider.isContinuous = true
            applySliderLayoutDirection()
        }

        // サムネイルストリップを追加
        let strip = ThumbnailStripView()
        strip.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(strip)
        thumbnailStripView = strip

        // 制約の再構成（サムネイルストリップをimageViewとスライダーの間に挿入）
        if let imageView, let pageLabel, let slider = pageSlider {
            // 既存の imageView と pageLabel の間の縦方向制約を解除
            let toRemove = view.constraints.filter { c in
                let f = c.firstItem as AnyObject?
                let s = c.secondItem as AnyObject?
                return (f === pageLabel && c.firstAttribute == .top && s === imageView && c.secondAttribute == .bottom)
                    || (f === imageView && c.firstAttribute == .bottom && s === pageLabel && c.secondAttribute == .top)
            }
            NSLayoutConstraint.deactivate(toRemove)

            // imageView.bottom → thumbnailStripView.top（常時）
            let stripTopConstraint = strip.topAnchor.constraint(equalTo: imageView.bottomAnchor)
            imageViewBottomToStripConstraint = stripTopConstraint
            let initialHeight = loadThumbnailStripHeight()
            lastVisibleThumbnailStripHeight = initialHeight
            let heightConstraint = strip.heightAnchor.constraint(equalToConstant: initialHeight)
            thumbnailStripHeightConstraint = heightConstraint
            NSLayoutConstraint.activate([
                stripTopConstraint,
                strip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                strip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                heightConstraint,
            ])

            strip.onResizeDragged = { [weak self] delta in
                guard let self, let constraint = self.thumbnailStripHeightConstraint else { return }
                let maxHeight = min(200, self.view.bounds.height * 0.5)
                constraint.constant = max(44, min(maxHeight, constraint.constant + delta))
            }
            strip.onResizeDragEnded = { [weak self] in
                guard let self, let constraint = self.thumbnailStripHeightConstraint else { return }
                self.saveThumbnailStripHeight(constraint.constant)
                self.lastVisibleThumbnailStripHeight = constraint.constant
                self.thumbnailStripView?.reloadThumbnails()
                // 内蔵ビューア側の KeyForwardingView へフォーカスを戻す
                DistributedNotificationCenter.default().post(
                    name: CZDistributedNotifications.sliderOperationCompleted,
                    object: nil
                )
            }

            // サムネイルストリップの下端をview下端に固定（非表示時は高さ0のため画像が全高になる）
            NSLayoutConstraint.activate([
                strip.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])

            // 旧UI（スライダー・ページラベル）は画像に重ねる進捗バーへ役割を移行。
            // 参照箇所が多いため値モデルとしてはインスタンスを保持しつつ、画面には表示しない。
            slider.isHidden = true
            pageLabel.isHidden = true
            let labelPositionConstraints = view.constraints.filter { c in
                let f = c.firstItem as AnyObject?
                let s = c.secondItem as AnyObject?
                return (f === pageLabel && s === view) || (f === view && s === pageLabel)
            }
            NSLayoutConstraint.deactivate(labelPositionConstraints)

            // 画像に重ねる進捗バー（プログレスバー）を設置
            setupPageProgressBar()
        }

        applyThumbnailStripVisibility(isThumbnailStripVisible)
    }

    /// 画像の上に重ねて表示する進捗バーを生成し、カーソル検知・シーク操作と接続する
    private func setupPageProgressBar() {
        guard let imageView, let overlay = cursorAreaOverlay else { return }

        let bar = PageProgressBarView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.isHidden = true
        bar.alphaValue = 0
        bar.isRightToLeftReading = isRightToLeftReading
        // 見開き時は rightImageView がオーバーレイより上に重なるため、最前面（末尾）に追加して両ページ上に表示されるようにする
        view.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            bar.heightAnchor.constraint(equalToConstant: 28),
            bar.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -12),
        ])
        bar.onSeek = { [weak self] page in
            self?.moveToPageViaSlider(page)
        }
        pageProgressBar = bar

        // カーソルが画像下部の帯に入ったら進捗バーを表示、画像領域を離れたら即座に消す
        overlay.onMouseMoved = { [weak self] point in
            self?.handlePagerHoverPoint(point)
        }
        overlay.onMouseExited = { [weak self] in
            self?.hidePagerImmediately()
        }

        refreshPager()
    }

    /// カーソル位置（画像領域内のローカル座標）を見て、下部の帯への出入りに応じて進捗バーを表示/非表示にする
    private func handlePagerHoverPoint(_ point: NSPoint) {
        if point.y <= pagerHoverBandHeight, imageManager.getImageCount() > 1 {
            showPager()
        } else {
            hidePagerImmediately()
        }
    }

    /// 進捗バーをフェード表示する
    private func showPager() {
        guard let bar = pageProgressBar, !isPagerVisible else { return }
        isPagerVisible = true
        bar.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            bar.animator().alphaValue = 1
        }
    }

    /// 進捗バーを即座にフェードアウトする（下部の帯から離れた・画像領域からカーソルが離れた時など）
    private func hidePagerImmediately() {
        guard let bar = pageProgressBar, isPagerVisible else { return }
        isPagerVisible = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            bar.animator().alphaValue = 0
        }, completionHandler: { [weak bar] in
            bar?.isHidden = true
        })
    }

    private func setupConstraintPriorities() {
        // ImageViewとPageLabelのAuto Layout制約を最適化
        guard let imageView = imageView, let pageLabel = pageLabel else { return }
        
        // ImageViewのContent Hugging/Compression Resistance優先度を調整
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        
        // 右側ImageViewも同様に設定
        if let rightImageView = rightImageView {
            rightImageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
            rightImageView.setContentHuggingPriority(.defaultLow, for: .vertical)
            rightImageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            rightImageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        }
        
        // PageLabelの優先度を高く設定（サイズを保持）
        pageLabel.setContentHuggingPriority(.required, for: .horizontal)
        pageLabel.setContentHuggingPriority(.required, for: .vertical)
        pageLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        pageLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    }
    
    private func setupViewModeConstraints() {
        guard let imageView = imageView, let rightImageView = rightImageView else {
            return
        }
        
        // 右側ImageViewをAuto Layoutに切り替える
        rightImageView.translatesAutoresizingMaskIntoConstraints = false
        
        // XIBの元のImageView制約を保存（見開き時に一時無効化するため）
        originalImageViewConstraints = view.constraints.filter { constraint in
            let firstItem = constraint.firstItem as AnyObject?
            let secondItem = constraint.secondItem as AnyObject?
            return (firstItem === imageView || secondItem === imageView) && 
                   (constraint.firstAttribute == .trailing || constraint.secondAttribute == .trailing)
        }
        
    // 単ページモードは XIB 既定制約を使用
        
        // 見開きモード用の制約
        spreadConstraints = [
            // 左側ImageViewの新しい制約（元の右端制約の代替）
            imageView.trailingAnchor.constraint(equalTo: view.centerXAnchor),
            // 右側ImageViewの制約
            rightImageView.leadingAnchor.constraint(equalTo: view.centerXAnchor),
            rightImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rightImageView.topAnchor.constraint(equalTo: imageView.topAnchor),
            rightImageView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor)
        ]
        
        // 単ページモードで開始
        currentViewMode = .single
    rightImageView.isHidden = true
    // 単ページ初期は中央寄せ
    imageView.imageAlignment = .alignCenter
    rightImageView.imageAlignment = .alignCenter
    }
    
    private func setupGestureRecognizers() {
        // フルスクリーンのため、クリックはローカルモニタで処理する
        // 右クリック用コンテキストメニュー
        view.menu = makeContextMenu()
    }

    private func makeContextMenu(includeDebugInfo: Bool = false) -> NSMenu {
        let menu = CZPreviewContextMenuFactory.makeMenu(
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
                    return ("0", [])
                case .setViewModeSingle:
                    return ("1", [])
                case .setViewModeSpread:
                    return ("2", [])
                case .setSpreadPairOffset:
                    return ("t", [])
                case .setThumbnailStripVisible:
                    return ("l", [])
                case .setSlideshowEnabled:
                    return ("s", [])
                default:
                    return nil
                }
            }
        )
        if includeDebugInfo {
            appendDebugMenuItems(to: menu)
        }
        return menu
    }

    private func appendDebugMenuItems(to menu: NSMenu) {
        menu.addItem(.separator())
        addDisabledMenuItem("Debug Information", to: menu)
        for line in makeDebugInformationLines() {
            addDisabledMenuItem(line, to: menu)
        }
    }

    private func addDisabledMenuItem(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func makeDebugInformationLines() -> [String] {
        let defaults = CZUserDefaults.shared
        let bundle = Bundle(for: PreviewViewController.self)
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = bundle.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "-"
        let bundleID = bundle.bundleIdentifier ?? "-"
        let previewSessionID = abbreviateIdentifier(previewVisibilitySessionID)
        let activeSessionID = abbreviateIdentifier(defaults.string(forKey: CZSettingsKeys.keyHelperActiveSessionID) ?? "-")

        return [
            "Viewer: \(version) (\(build))",
            "Bundle: \(bundleID)",
            "Host: \(ProcessInfo.processInfo.processName)",
            "File: \(currentZipFilename.isEmpty ? "-" : currentZipFilename)",
            "Page: \(imageManager.getCurrentPageNumber()) / \(imageManager.getImageCount())",
            "Mode: \(viewModeText(currentViewMode)) pref=\(userPreferredViewMode.rawValue)",
            "Session: \(previewSessionID)",
            "Preview RTL: \(boolText(isRightToLeftReading))",
            "Global RTL: \(boolText(defaults.object(forKey: CZSettingsKeys.isRightToLeftReading) as? Bool))",
            "KeyHelper enabled: \(boolText(defaults.object(forKey: CZSettingsKeys.isKeyHelperEnabled) as? Bool))",
            "KeyHelper AX: \(boolText(defaults.object(forKey: CZSettingsKeys.keyHelperLastAccessibilityTrusted) as? Bool)) tap=\(boolText(defaults.object(forKey: CZSettingsKeys.keyHelperIsEventTapInstalled) as? Bool))",
            "KeyHelper active: \(activeSessionID) until=\(dateText(defaults.double(forKey: CZSettingsKeys.keyHelperVisibleUntil)))",
            "Last key: \(lastKeyText(defaults: defaults))",
            "Last command: \(lastCommandText(defaults: defaults))",
            "Last decision: \(defaults.string(forKey: CZSettingsKeys.keyHelperLastDecision) ?? "-")",
            "Window: \(defaults.string(forKey: CZSettingsKeys.keyHelperLastWindowSummary) ?? "-")"
        ]
    }

    private func viewModeText(_ viewMode: ViewMode) -> String {
        switch viewMode {
        case .single:
            return "single"
        case .spread:
            return "spread"
        }
    }

    private func boolText(_ value: Bool?) -> String {
        guard let value else { return "-" }
        return value ? "true" : "false"
    }

    private func dateText(_ timestamp: Double) -> String {
        guard timestamp > 0 else { return "-" }
        return Self.debugDateFormatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    private func lastKeyText(defaults: UserDefaults) -> String {
        let timestamp = defaults.double(forKey: CZSettingsKeys.keyHelperLastKeyAt)
        guard timestamp > 0 else { return "-" }
        let keyCode = defaults.object(forKey: CZSettingsKeys.keyHelperLastKeyCode) as? Int
        return "\(keyCode.map { String($0) } ?? "?") at \(dateText(timestamp))"
    }

    private func lastCommandText(defaults: UserDefaults) -> String {
        let timestamp = defaults.double(forKey: CZSettingsKeys.keyHelperLastCommandAt)
        guard timestamp > 0 else { return "-" }
        let command = defaults.string(forKey: CZSettingsKeys.keyHelperLastCommand) ?? "?"
        return "\(command) at \(dateText(timestamp))"
    }

    private func abbreviateIdentifier(_ value: String) -> String {
        guard value.count > 12 else { return value }
        return "\(value.prefix(8))..."
    }

    private static let debugDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
    
    private func updateContextMenuStates() {
        // コンテキストメニューを再作成して状態を更新
        view.menu = makeContextMenu()
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
            return #selector(toggleSpreadPairingOffset(_:))
        case .setThumbnailStripVisible:
            return #selector(toggleThumbnailStripVisibility(_:))
        case .setPageTransitionEnabled:
            return #selector(toggleTransition(_:))
        case .setSlideshowEnabled:
            return #selector(toggleSlideshow(_:))
        case .goToFirstPage, .goToLastPage, .goForwardPage, .goBackwardPage,
             .goLeftArrowPage, .goRightArrowPage, .jumpLeftArrowPages, .jumpRightArrowPages,
             .goToLeftArrowEdgePage, .goToRightArrowEdgePage, .jumpRelativePages:
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
            return userPreferredViewMode == .auto ? .on : .off
        case .setViewModeSingle:
            return userPreferredViewMode == .single ? .on : .off
        case .setViewModeSpread:
            return userPreferredViewMode == .spread ? .on : .off
        case .setSpreadPairOffset:
            return imageManager.getSpreadPairOffset() == 1 ? .on : .off
        case .setThumbnailStripVisible:
            return isThumbnailStripVisible ? .on : .off
        case .setPageTransitionEnabled:
            return isTransitionEnabled ? .on : .off
        case .setSlideshowEnabled:
            return isSlideshowEnabled ? .on : .off
        case .goToFirstPage, .goToLastPage, .goForwardPage, .goBackwardPage,
             .goLeftArrowPage, .goRightArrowPage, .jumpLeftArrowPages, .jumpRightArrowPages,
             .goToLeftArrowEdgePage, .goToRightArrowEdgePage, .jumpRelativePages:
            return .off
        }
    }

    @objc private func toggleSpreadPairingOffset(_ sender: NSMenuItem) {
        applySpreadPairOffset(1 - imageManager.getSpreadPairOffset())
    }
    
    // 表示モード切替アクション
    @objc private func setViewModeAuto(_ sender: NSMenuItem) {
        applyViewModePreference(.auto)
    }
    
    @objc private func setViewModeSingle(_ sender: NSMenuItem) {
        applyViewModePreference(.single)
    }
    
    @objc private func setViewModeSpread(_ sender: NSMenuItem) {
        applyViewModePreference(.spread)
    }
    
    // 読み方向切替アクション
    @objc private func setRightToLeft(_ sender: NSMenuItem) {
        applyReadingDirection(true, persistGlobalSetting: true)
        postReadingDirectionChanged(isRightToLeft: true)
    }

    @objc private func setLeftToRight(_ sender: NSMenuItem) {
        applyReadingDirection(false, persistGlobalSetting: true)
        postReadingDirectionChanged(isRightToLeft: false)
    }

    private func postReadingDirectionChanged(isRightToLeft: Bool) {
        DistributedNotificationCenter.default().postNotificationName(
            CZDistributedNotifications.settingsChanged,
            object: nil,
            userInfo: [
                CZSettingsKeys.isRightToLeftReading: isRightToLeft,
                CZPreviewVisibilityUserInfoKeys.sessionID: previewVisibilitySessionID
            ],
            deliverImmediately: true
        )
    }
    
    @objc private func toggleSlideshow(_ sender: NSMenuItem) {
        applySlideshowEnabled(!isSlideshowEnabled)
    }

    @objc private func toggleThumbnailStripVisibility(_ sender: NSMenuItem) {
        applyThumbnailStripVisibility(!isThumbnailStripVisible)
    }

    private func applyViewModePreference(_ viewMode: ViewModePreference) {
        userPreferredViewMode = viewMode
        didRestoreViewModeFromHistory = true
        displayCurrentImage()
        updateContextMenuStates()
        saveReadingPositionToHistory()
    }

    private func applyReadingDirection(_ isRightToLeft: Bool, persistGlobalSetting: Bool = false) {
        if persistGlobalSetting {
            CZUserDefaults.shared.set(isRightToLeft, forKey: CZSettingsKeys.isRightToLeftReading)
            CZUserDefaults.shared.synchronize()
        }
        isRightToLeftReading = isRightToLeft
        didRestoreRTLFromHistory = true
        thumbnailStripView?.isRightToLeft = isRightToLeft

        applySliderLayoutDirection()
        syncSliderToCurrentPage()
        displayCurrentImage()
        updateContextMenuStates()
        saveReadingPositionToHistory()
    }

    private func applySpreadPairOffset(_ offset: Int) {
        imageManager.setSpreadPairOffset((offset % 2 + 2) % 2)
        displayCurrentImage()
        updateContextMenuStates()
    }

    private func applyTransitionEnabled(_ enabled: Bool) {
        isTransitionEnabled = enabled
        updateContextMenuStates()
    }

    private func applySlideshowEnabled(_ enabled: Bool) {
        if enabled {
            startSlideshow()
        } else {
            stopSlideshow()
        }
        updateContextMenuStates()
    }

    private func applyThumbnailStripVisibility(_ isVisible: Bool) {
        isThumbnailStripVisible = isVisible

        guard let strip = thumbnailStripView,
              let heightConstraint = thumbnailStripHeightConstraint else {
            return
        }

        if isVisible {
            let resolvedHeight = max(44, lastVisibleThumbnailStripHeight)
            heightConstraint.constant = resolvedHeight
            strip.isHidden = false
        } else {
            if heightConstraint.constant > 0 {
                lastVisibleThumbnailStripHeight = heightConstraint.constant
            }
            heightConstraint.constant = 0
            strip.isHidden = true
        }

        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        updateContextMenuStates()
    }

    private func setupDistributedNotificationObserversIfNeeded() {
        guard !hasSetupDistributedNotificationObservers else { return }
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            self,
            selector: #selector(handleSettingsChangedNotification(_:)),
            name: CZDistributedNotifications.settingsChanged,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        center.addObserver(
            self,
            selector: #selector(handlePreviewSessionCommandNotification(_:)),
            name: CZDistributedNotifications.previewSessionCommand,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        hasSetupDistributedNotificationObservers = true
    }

    private func teardownDistributedNotificationObservers() {
        guard hasSetupDistributedNotificationObservers else { return }
        let center = DistributedNotificationCenter.default()
        center.removeObserver(self, name: CZDistributedNotifications.settingsChanged, object: nil)
        center.removeObserver(self, name: CZDistributedNotifications.previewSessionCommand, object: nil)
        hasSetupDistributedNotificationObservers = false
    }

    @objc private func handleSettingsChangedNotification(_ notification: Notification) {
        // 最新設定を共有UserDefaultsから再取得
        let newRTL = AppSettings.shared.isRightToLeftReading
        if !didRestoreRTLFromHistory && newRTL != isRightToLeftReading {
            isRightToLeftReading = newRTL
            thumbnailStripView?.isRightToLeft = isRightToLeftReading
            applySliderLayoutDirection()
            syncSliderToCurrentPage()
        }
        let newTransition = AppSettings.shared.pageTransitionEnabled
        if newTransition != isTransitionEnabled { isTransitionEnabled = newTransition }
        let newThumbnailStripVisible = AppSettings.shared.isThumbnailStripVisible
        if newThumbnailStripVisible != isThumbnailStripVisible {
            applyThumbnailStripVisibility(newThumbnailStripVisible)
        }
        let newSlideshowEnabled = AppSettings.shared.isSlideshowEnabled
        if newSlideshowEnabled != isSlideshowEnabled {
            applySlideshowEnabled(newSlideshowEnabled)
        }
        let newViewMode = AppSettings.shared.defaultViewMode
        if !didRestoreViewModeFromHistory && newViewMode != userPreferredViewMode {
            userPreferredViewMode = newViewMode
        }
        let newSpreadOffset = CZUserDefaults.shared.object(forKey: CZSettingsKeys.spreadPairOffset) as? Int ?? 0
        if imageManager.getSpreadPairOffset() != newSpreadOffset {
            imageManager.setSpreadPairOffset(newSpreadOffset)
        }
        imageManager.refreshDecodeCachePolicy()
        // 表示更新
        if imageManager.hasImages() {
            displayCurrentImage()
        }
        // メニュー状態を更新
        updateContextMenuStates()
    }

    @objc private func handlePreviewSessionCommandNotification(_ notification: Notification) {
        handlePreviewSessionCommand(notification)
    }

    private func handlePreviewSessionCommand(_ notification: Notification) {
        let userInfo = notification.userInfo ?? [:]
        let commandRaw = (userInfo[CZPreviewSessionCommandUserInfoKeys.command] as? String) ?? (notification.object as? String)
        guard let commandRaw,
              let command = CZPreviewSessionCommand(rawValue: commandRaw) else {
            return
        }
        postPreviewSessionCommandHandled(commandID: userInfo[CZPreviewSessionCommandUserInfoKeys.commandID] as? String)

        switch command {
        case .setRightToLeftReading:
            applyReadingDirection(true)
        case .setLeftToRightReading:
            applyReadingDirection(false)
        case .setViewModeAuto:
            applyViewModePreference(.auto)
        case .setViewModeSingle:
            applyViewModePreference(.single)
        case .setViewModeSpread:
            applyViewModePreference(.spread)
        case .setSpreadPairOffset:
            let offset = userInfo[CZPreviewSessionCommandUserInfoKeys.intValue] as? Int ?? (1 - imageManager.getSpreadPairOffset())
            applySpreadPairOffset(offset)
        case .setThumbnailStripVisible:
            let isVisible = userInfo[CZPreviewSessionCommandUserInfoKeys.boolValue] as? Bool ?? !isThumbnailStripVisible
            applyThumbnailStripVisibility(isVisible)
        case .setPageTransitionEnabled:
            let enabled = userInfo[CZPreviewSessionCommandUserInfoKeys.boolValue] as? Bool ?? !isTransitionEnabled
            applyTransitionEnabled(enabled)
        case .setSlideshowEnabled:
            let enabled = userInfo[CZPreviewSessionCommandUserInfoKeys.boolValue] as? Bool ?? !isSlideshowEnabled
            NSLog("[DEBUG] Received setSlideshowEnabled command: %d", enabled ? 1 : 0)
            applySlideshowEnabled(enabled)
        case .goToFirstPage:
            moveToPageFromThumbnail(1)
        case .goToLastPage:
            moveToPageFromThumbnail(imageManager.getImageCount())
        case .goForwardPage:
            _ = performPageNavigation(forward: true)
        case .goBackwardPage:
            _ = performPageNavigation(forward: false)
        case .goLeftArrowPage:
            _ = performPageNavigation(forward: isRightToLeftReading)
        case .goRightArrowPage:
            _ = performPageNavigation(forward: !isRightToLeftReading)
        case .jumpLeftArrowPages:
            jumpArrowPages(isLeftArrow: true, userInfo: userInfo)
        case .jumpRightArrowPages:
            jumpArrowPages(isLeftArrow: false, userInfo: userInfo)
        case .goToLeftArrowEdgePage:
            moveToArrowEdgePage(isLeftArrow: true)
        case .goToRightArrowEdgePage:
            moveToArrowEdgePage(isLeftArrow: false)
        case .jumpRelativePages:
            let delta = userInfo[CZPreviewSessionCommandUserInfoKeys.intValue] as? Int ?? 0
            jumpRelativePages(delta)
        }
    }

    private func jumpArrowPages(isLeftArrow: Bool, userInfo: [AnyHashable: Any]) {
        let pageCount = userInfo[CZPreviewSessionCommandUserInfoKeys.intValue] as? Int ?? 10
        let isForward = isLeftArrow == isRightToLeftReading
        jumpRelativePages(isForward ? pageCount : -pageCount)
    }

    private func moveToArrowEdgePage(isLeftArrow: Bool) {
        let isForward = isLeftArrow == isRightToLeftReading
        moveToPageFromThumbnail(isForward ? imageManager.getImageCount() : 1)
    }

    private func jumpRelativePages(_ delta: Int) {
        let target = imageManager.getCurrentPageNumber() + delta
        let clamped = max(1, min(target, imageManager.getImageCount()))
        moveToPageFromThumbnail(clamped)
    }

    private func postPreviewSessionCommandHandled(commandID: String?) {
        guard let commandID else { return }
        DistributedNotificationCenter.default().postNotificationName(
            CZDistributedNotifications.previewSessionCommandHandled,
            object: commandID,
            userInfo: [CZPreviewSessionCommandUserInfoKeys.commandID: commandID],
            deliverImmediately: true
        )
    }
    
    private func startSlideshow() {
        guard !isSlideshowEnabled else { return }
        NSLog("[DEBUG] startSlideshow")
        isSlideshowEnabled = true
        
        let interval = AppSettings.shared.slideshowInterval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.advanceSlideshow()
        }
        slideshowTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    
    private func stopSlideshow() {
        NSLog("[DEBUG] stopSlideshow")
        isSlideshowEnabled = false
        slideshowTimer?.invalidate()
        slideshowTimer = nil
    }
    
    private func advanceSlideshow() {
        let isSpreadMode = currentViewMode == .spread
        
        // 常に「進む」方向
        if !imageManager.nextImage(isSpreadMode: isSpreadMode) {
            // 最後のページに到達したらスライドショーを停止
            stopSlideshow()
            return
        }

        // レイアウトを決定してからトランジション→描画
        setViewMode(shouldUseSpreadMode() ? .spread : .single)
        applyTransition(forward: true)
        displayCurrentImage()
    }
    
    private func setViewMode(_ mode: ViewMode) {
        guard currentViewMode != mode else { return }
        
        currentViewMode = mode
        
        switch mode {
        case .single:
            // 見開き制約を無効化
            NSLayoutConstraint.deactivate(spreadConstraints)
            // 元のImageView制約を復活
            NSLayoutConstraint.activate(originalImageViewConstraints)
            rightImageView?.isHidden = true
            // 単ページは中央寄せ
            imageView?.imageAlignment = .alignCenter
            rightImageView?.imageAlignment = .alignCenter
            
        case .spread:
            // 元のImageView制約を無効化（競合回避）
            NSLayoutConstraint.deactivate(originalImageViewConstraints)
            // 見開き制約を有効化
            NSLayoutConstraint.activate(spreadConstraints)
            rightImageView?.isHidden = false
            // 見開き時は内側に寄せる（中央でくっつける）
            // 左画像は右寄せ、右画像は左寄せ
            imageView?.imageAlignment = .alignRight
            rightImageView?.imageAlignment = .alignLeft
        }
        
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
    }
    
    private func shouldUseSpreadMode() -> Bool {
        let alwaysSingleForCover = AppSettings.shared.alwaysSinglePageForCover
        let isCover = imageManager.isCoverPage()
        
        // 表紙で「常に単ページ表示」が有効な場合は単ページを強制
        if alwaysSingleForCover && isCover {
            return false
        }
        
        // ユーザー設定モードに基づく判定
        switch userPreferredViewMode {
        case .auto:
            // 自動モード：ウィンドウの縦横比で判定
            let bounds = view.bounds
            let isLandscape = bounds.width > bounds.height
            return isLandscape
            
        case .single:
            // 単ページ固定モード
            return false
            
        case .spread:
            // 見開き固定モード
            return true
        }
    }

    private func applyInitialViewModeIfNeeded() {
        guard !didApplyInitialViewMode else { return }
        didApplyInitialViewMode = true
        
        // 初期表示モードを適用（ユーザー設定は既にviewDidLoadで読み込み済み）
        NSLog("[DEBUG] Applying initial view mode: %@", userPreferredViewMode.rawValue)
        let useSpread = shouldUseSpreadMode()
        NSLog("[DEBUG] shouldUseSpreadMode result: %d", useSpread)
        setViewMode(useSpread ? .spread : .single)
    }
    
    @objc private func handleClick(_ gesture: NSClickGestureRecognizer) {}

    // ダブルクリック時は何もしない（シングルクリックハンドラで検知して無視）
    
    // MARK: - 画像表示

    private func buildCurrentDisplayKey() -> String {
        let modeToken = currentViewMode == .spread ? "spread" : "single"
        let bounds = view.bounds
        return "\(imageManager.getCurrentPageNumber())_\(modeToken)_\(isRightToLeftReading ? 1 : 0)_\(imageManager.getSpreadPairOffset())_\(Int(bounds.width))x\(Int(bounds.height))"
    }

    private func scheduleDisplayCurrentImageIfNeeded() {
        guard !isDisplayCurrentImageScheduled else { return }
        isDisplayCurrentImageScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isDisplayCurrentImageScheduled = false
            self.displayCurrentImage()
        }
    }

    private func resetDisplayRequestLatchesIfNeeded(for displayKey: String) {
        guard displayKey != lastDisplayKey else { return }
        lastPrerenderRefreshKey = nil
        lastPrerenderRequestKey = nil
        lastPrerenderApplyRetryKey = nil
        lastImageFallbackRequestKey = nil
        lastTinyFallbackRequestKey = nil
        lastDisplayKey = displayKey
    }
    
    private func displayCurrentImage() {
        let now = CACurrentMediaTime()
        if !isDisplayCurrentImageInFlight, (now - lastDisplayCurrentImageTimestamp) < minDisplayCurrentImageInterval {
            scheduleDisplayCurrentImageIfNeeded()
            return
        }
        if isDisplayCurrentImageInFlight {
            needsDisplayCurrentImageRetry = true
            return
        }

        isDisplayCurrentImageInFlight = true
        lastDisplayCurrentImageTimestamp = now
        defer {
            isDisplayCurrentImageInFlight = false
            if needsDisplayCurrentImageRetry {
                needsDisplayCurrentImageRetry = false
                scheduleDisplayCurrentImageIfNeeded()
            }
        }

        os_signpost(.begin, log: performanceLog, name: "displayCurrentImage")
        // アスペクト比に基づいて表示モードを決定
        let useSpread = shouldUseSpreadMode()
        
        setViewMode(useSpread ? .spread : .single)
        resetDisplayRequestLatchesIfNeeded(for: buildCurrentDisplayKey())
        
        if useSpread {
            displaySpreadImages(usePrerender: true)
        } else {
            displaySingleImage(usePrerender: true)
        }
        
        updatePageLabel()
        // スライダーの位置を現在ページに同期（方向反転に対応）
        let skipThumb = skipThumbnailSyncOnce
        skipThumbnailSyncOnce = false
        syncSliderToCurrentPage(skipThumbnailSync: skipThumb)
        updatePreferredContentSizeIfNeeded()
        os_signpost(.end, log: performanceLog, name: "displayCurrentImage")
    }
    
    private func updateImageDisplayOnly() {
        // 固定モード用：現在のViewModeを維持したまま画像表示のみ更新
        let currentMode = currentViewMode
        resetDisplayRequestLatchesIfNeeded(for: buildCurrentDisplayKey())
        
        if currentMode == .spread {
            displaySpreadImages(usePrerender: true)
        } else {
            displaySingleImage(usePrerender: true)
        }
        
        updatePageLabel()
        syncSliderToCurrentPage()
        updatePreferredContentSizeIfNeeded()
    }

    private func displaySingleImage(usePrerender: Bool) {
        clearPrerenderedLayers()
        let displayKey = buildCurrentDisplayKey()

        if usePrerender, let cachedLayer = imageManager.getCurrentPrerenderedLayer() {
            os_signpost(.event, log: performanceLog, name: "layerCacheHit", "mode=single")
            let cachedImage = imageManager.getCurrentImageIfCachedOnly(quality: .normal)
                ?? (Self.isLowQualityFallbackEnabled ? imageManager.getCurrentImageIfCachedOnly(quality: .low) : nil)
            // 下敷きはプリレンダーレイヤーが初回だけ描画されない場合の安全網。
            // 通常キャッシュ画像があるなら白紙/tinyではなく実画像を残す。
            let underlayImage = cachedImage
                ?? imageManager.cachedTinyImage(at: imageManager.getCurrentPageNumber() - 1)
                ?? makeWhitePagePlaceholder(aspect: lastKnownSinglePageAspect)
            let didApplyPrerender = setPrerenderedLayer(cachedLayer, toImageView: imageView, fallbackImage: underlayImage)
            if !didApplyPrerender {
                setImageSafely(cachedImage ?? underlayImage, toImageView: imageView)
            }
            if didApplyPrerender {
                lastPrerenderApplyRetryKey = nil
            } else if lastPrerenderApplyRetryKey != displayKey {
                lastPrerenderApplyRetryKey = displayKey
                scheduleDisplayCurrentImageIfNeeded()
            }
            if let cachedImage {
                updateSinglePageAspect(from: cachedImage)
            }
            lastPrerenderRequestKey = nil
        } else if usePrerender {
            if let currentImage = imageManager.getCurrentImageIfCachedOnly(quality: .normal)
                ?? (Self.isLowQualityFallbackEnabled ? imageManager.getCurrentImageIfCachedOnly(quality: .low) : nil) {
                setImageSafely(currentImage, toImageView: imageView)
                updateSinglePageAspect(from: currentImage)
            } else {
                let pageIndex = imageManager.getCurrentPageNumber() - 1
                if let tinyImage = imageManager.cachedTinyImage(at: pageIndex) {
                    // tinyキャッシュ（サムネイル共有）があれば白ページの代わりに低解像度画像を表示する
                    setImageSafely(tinyImage, toImageView: imageView)
                    updateSinglePageAspect(from: tinyImage)
                } else {
                    // 現在ページ画像が未準備の間、前ページ画像が残らないように白ページを表示する
                    setImageSafely(makeWhitePagePlaceholder(aspect: lastKnownSinglePageAspect), toImageView: imageView)
                    requestTinyFallbackImageIfNeeded(displayKey: displayKey, pageIndex: pageIndex)
                }
                requestSingleFallbackImageIfNeeded(displayKey: displayKey)
            }
            if lastPrerenderRequestKey != displayKey {
                os_signpost(.event, log: performanceLog, name: "layerCacheMiss", "mode=single")
                lastPrerenderRequestKey = displayKey
                imageManager.prerenderCurrentLayerIfNeeded()
            }
        } else if let currentImage = imageManager.getCurrentImage() {
            setImageSafely(currentImage, toImageView: imageView)
            updateSinglePageAspect(from: currentImage)
        }

        imageManager.preloadAdjacentImages(isSpreadMode: false, isRightToLeft: isRightToLeftReading)
    }

    private func displaySpreadImages(usePrerender: Bool) {
        clearPrerenderedLayers()
        let displayKey = buildCurrentDisplayKey()
        let spreadImages: (left: NSImage?, right: NSImage?)
        if usePrerender {
            let normalImages = imageManager.getSpreadImagesIfCachedOnly(isRightToLeft: isRightToLeftReading, quality: .normal)
            let lowImages: (left: NSImage?, right: NSImage?) = Self.isLowQualityFallbackEnabled
                ? imageManager.getSpreadImagesIfCachedOnly(isRightToLeft: isRightToLeftReading, quality: .low)
                : (nil, nil)
            spreadImages = (
                left: normalImages.left ?? lowImages.left,
                right: normalImages.right ?? lowImages.right
            )
        } else {
            spreadImages = imageManager.getSpreadImages(isRightToLeft: isRightToLeftReading)
        }
        let spreadPairIndices = imageManager.getCurrentSpreadPairIndices(isRightToLeft: isRightToLeftReading)

        if usePrerender, let cachedLayers = imageManager.getSpreadPrerenderedLayers(isRightToLeft: isRightToLeftReading) {
            os_signpost(.event, log: performanceLog, name: "layerCacheHit", "mode=spread")
            // 下敷きはプリレンダーレイヤーが初回だけ描画されない場合の安全網。
            // 通常キャッシュ画像があるなら白紙/tinyではなく実画像を残す。
            let leftUnderlay = spreadImages.left ?? makeSpreadPlaceholderIfNeeded(side: .left, pageIndex: spreadPairIndices.left)
            let rightUnderlay = spreadImages.right ?? makeSpreadPlaceholderIfNeeded(side: .right, pageIndex: spreadPairIndices.right)
            let didApplyLeft = setPrerenderedLayer(cachedLayers.left, toImageView: imageView, fallbackImage: leftUnderlay, side: .left)
            let didApplyRight = setPrerenderedLayer(cachedLayers.right, toImageView: rightImageView, fallbackImage: rightUnderlay, side: .right)
            if !didApplyLeft {
                setSpreadImageOrPlaceholder(spreadImages.left, toImageView: imageView, side: .left, pageIndex: spreadPairIndices.left)
            } else if let leftImage = spreadImages.left {
                updateSpreadPageAspect(from: leftImage, side: .left)
            }
            if !didApplyRight {
                setSpreadImageOrPlaceholder(spreadImages.right, toImageView: rightImageView, side: .right, pageIndex: spreadPairIndices.right)
            } else if let rightImage = spreadImages.right {
                updateSpreadPageAspect(from: rightImage, side: .right)
            }
            let didFailExpectedLayer = (cachedLayers.left != nil && !didApplyLeft) || (cachedLayers.right != nil && !didApplyRight)
            if !didFailExpectedLayer {
                lastPrerenderApplyRetryKey = nil
            } else if lastPrerenderApplyRetryKey != displayKey {
                lastPrerenderApplyRetryKey = displayKey
                scheduleDisplayCurrentImageIfNeeded()
            }
            lastPrerenderRequestKey = nil
        } else {
            setSpreadImageOrPlaceholder(spreadImages.left, toImageView: imageView, side: .left, pageIndex: spreadPairIndices.left)
            setSpreadImageOrPlaceholder(spreadImages.right, toImageView: rightImageView, side: .right, pageIndex: spreadPairIndices.right)
            if spreadImages.left == nil || spreadImages.right == nil {
                requestSpreadFallbackImagesIfNeeded(displayKey: displayKey)
                requestSpreadTinyFallbackImagesIfNeeded(
                    displayKey: displayKey,
                    pairIndices: spreadPairIndices,
                    missingLeft: spreadImages.left == nil,
                    missingRight: spreadImages.right == nil
                )
            }
            if lastPrerenderRequestKey != displayKey {
                os_signpost(.event, log: performanceLog, name: "layerCacheMiss", "mode=spread")
                lastPrerenderRequestKey = displayKey
                imageManager.prerenderSpreadLayersIfNeeded(isRightToLeft: isRightToLeftReading)
            }
        }

        calculateSpreadAspectRatio(leftImage: spreadImages.left, rightImage: spreadImages.right)
        imageManager.preloadAdjacentImages(isSpreadMode: true, isRightToLeft: isRightToLeftReading)
    }

    private func setSpreadImageOrPlaceholder(_ image: NSImage?, toImageView imageView: NSImageView?, side: SpreadPageSide, pageIndex: Int?) {
        if let image {
            setImageSafely(image, toImageView: imageView)
            updateSpreadPageAspect(from: image, side: side)
            return
        }

        let placeholder = spreadPlaceholder(side: side, pageIndex: pageIndex)
        setImageSafely(placeholder.image, toImageView: imageView)
        if placeholder.isTinyContent, let tinyImage = placeholder.image {
            updateSpreadPageAspect(from: tinyImage, side: side)
        }
    }

    private func makeSpreadPlaceholderIfNeeded(side: SpreadPageSide, pageIndex: Int?) -> NSImage? {
        spreadPlaceholder(side: side, pageIndex: pageIndex).image
    }

    /// 指定ページのtinyキャッシュ画像があればそれを、無ければ白ページプレースホルダを返す（pageIndexがnilなら何も表示しない）
    private func spreadPlaceholder(side: SpreadPageSide, pageIndex: Int?) -> (image: NSImage?, isTinyContent: Bool) {
        guard let pageIndex else { return (nil, false) }
        if let tinyImage = imageManager.cachedTinyImage(at: pageIndex) {
            return (tinyImage, true)
        }

        switch side {
        case .left:
            return (makeWhitePagePlaceholder(aspect: lastKnownLeftPageAspect), false)
        case .right:
            return (makeWhitePagePlaceholder(aspect: lastKnownRightPageAspect), false)
        }
    }

    private func updateSinglePageAspect(from image: NSImage) {
        guard let aspect = pageAspect(from: image) else { return }
        lastKnownSinglePageAspect = aspect
        currentImageAspect = aspect
    }

    private func updateSpreadPageAspect(from image: NSImage, side: SpreadPageSide) {
        guard let aspect = pageAspect(from: image) else { return }

        switch side {
        case .left:
            lastKnownLeftPageAspect = aspect
        case .right:
            lastKnownRightPageAspect = aspect
        }
    }

    private func pageAspect(from image: NSImage) -> CGFloat? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        return image.size.width / image.size.height
    }

    private func makeWhitePagePlaceholder(aspect: CGFloat?) -> NSImage {
        let sanitizedAspect = max(0.1, min(aspect ?? defaultWhitePageAspect, 4.0))
        let cacheKey = Int((sanitizedAspect * 1000).rounded())
        if let cached = whitePagePlaceholderCache[cacheKey] {
            return cached
        }

        let imageSize = NSSize(
            width: whitePagePlaceholderHeight * sanitizedAspect,
            height: whitePagePlaceholderHeight
        )
        let image = NSImage(size: imageSize)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: imageSize).fill()
        image.unlockFocus()
        whitePagePlaceholderCache[cacheKey] = image
        return image
    }

    /// 指定ページが現在の表示対象（単ページ=現在ページ、見開き=左右ペアのいずれか）かを返す。
    /// 完了コールバックの再描画判定はdisplayKey完全一致だと微小リサイズで取りこぼすため、ページ一致で判定する
    private func isPageIndexCurrentlyDisplayed(_ index: Int) -> Bool {
        if currentViewMode == .spread {
            let pair = imageManager.getCurrentSpreadPairIndices(isRightToLeft: isRightToLeftReading)
            return pair.left == index || pair.right == index
        }
        return index == imageManager.getCurrentPageNumber() - 1
    }

    private func requestSingleFallbackImageIfNeeded(displayKey: String) {
        guard lastImageFallbackRequestKey != displayKey else { return }
        lastImageFallbackRequestKey = displayKey

        let targetIndex = imageManager.getCurrentPageNumber() - 1
        // フォールバック要求はprerender失敗時の白ページ復帰の安全網のため.low停止中も維持し、品質のみ.normalに切り替える
        let fallbackQuality: ImageManager.DecodeQualityTier = Self.isLowQualityFallbackEnabled ? .low : .normal
        imageManager.requestImageAsync(at: targetIndex, isSpreadMode: false, quality: fallbackQuality) { [weak self] pageIndex, image in
            guard let self else { return }
            guard self.isPageIndexCurrentlyDisplayed(pageIndex) else { return }
            guard image != nil else {
                // 失敗時はラッチを解除し、次の表示パスで再要求できるようにする
                self.lastImageFallbackRequestKey = nil
                return
            }
            self.scheduleDisplayCurrentImageIfNeeded()
        }
    }

    private func requestSpreadFallbackImagesIfNeeded(displayKey: String) {
        guard lastImageFallbackRequestKey != displayKey else { return }
        lastImageFallbackRequestKey = displayKey

        let targetBaseIndex = imageManager.getCurrentPageNumber() - 1
        let targetRTL = isRightToLeftReading
        // フォールバック要求はprerender失敗時の白ページ復帰の安全網のため.low停止中も維持し、品質のみ.normalに切り替える
        let fallbackQuality: ImageManager.DecodeQualityTier = Self.isLowQualityFallbackEnabled ? .low : .normal
        imageManager.requestSpreadImagesAsync(baseIndex: targetBaseIndex, isRightToLeft: targetRTL, quality: fallbackQuality) { [weak self] baseIndex, images in
            guard let self else { return }
            guard baseIndex == self.imageManager.getCurrentPageNumber() - 1 else { return }
            guard images.left != nil || images.right != nil else {
                // 失敗時はラッチを解除し、次の表示パスで再要求できるようにする
                self.lastImageFallbackRequestKey = nil
                return
            }
            self.scheduleDisplayCurrentImageIfNeeded()
        }
    }

    /// 単ページ表示で白ページプレースホルダ中の場合に、tinyキャッシュの取得をリクエストする
    private func requestTinyFallbackImageIfNeeded(displayKey: String, pageIndex: Int) {
        guard lastTinyFallbackRequestKey != displayKey else { return }
        lastTinyFallbackRequestKey = displayKey
        requestTinyImage(at: pageIndex)
    }

    /// 見開き表示で白ページプレースホルダ中のページがある場合に、tinyキャッシュの取得をリクエストする
    private func requestSpreadTinyFallbackImagesIfNeeded(displayKey: String, pairIndices: (left: Int?, right: Int?), missingLeft: Bool, missingRight: Bool) {
        guard lastTinyFallbackRequestKey != displayKey else { return }
        lastTinyFallbackRequestKey = displayKey

        if missingLeft, let leftIndex = pairIndices.left, imageManager.cachedTinyImage(at: leftIndex) == nil {
            requestTinyImage(at: leftIndex)
        }
        if missingRight, let rightIndex = pairIndices.right, imageManager.cachedTinyImage(at: rightIndex) == nil {
            requestTinyImage(at: rightIndex)
        }
    }

    private func requestTinyImage(at pageIndex: Int) {
        // isStillNeededはデコードキュー上で呼ばれるためメインスレッド状態を参照しない。
        // デコード結果はtinyキャッシュとして残り無駄にならないので常に続行し、
        // 表示の要否はcompletion側（メインスレッド）のページ一致判定で行う
        imageManager.requestTinyImage(at: pageIndex, maxPixelSize: 0, isStillNeeded: { true }) { [weak self] index, image in
            guard let self else { return }
            guard self.isPageIndexCurrentlyDisplayed(index) else { return }
            guard image != nil else {
                // 失敗時はラッチを解除し、次の表示パスで再要求できるようにする
                self.lastTinyFallbackRequestKey = nil
                return
            }
            self.scheduleDisplayCurrentImageIfNeeded()
        }
    }


    private func calculateSpreadAspectRatio(leftImage: NSImage?, rightImage: NSImage?) {
        // 見開き表示時の合成アスペクト比を計算
        var totalWidth: CGFloat = 0
        var maxHeight: CGFloat = 0
        
        if let left = leftImage {
            totalWidth += left.size.width
            maxHeight = max(maxHeight, left.size.height)
        }
        
        if let right = rightImage {
            totalWidth += right.size.width
            maxHeight = max(maxHeight, right.size.height)
        }
        
        if maxHeight > 0 {
            currentImageAspect = totalWidth / maxHeight
        } else {
            currentImageAspect = nil
        }
    }
    
    private func displayNoImagesMessage() {
        // 画像が見つからない場合のメッセージ表示
        let noImageText = "アーカイブ内に画像が見つかりませんでした"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let attributedString = NSAttributedString(string: noImageText, attributes: attributes)
        
        // テキスト用のImageを作成
        let textSize = attributedString.size()
        let image = NSImage(size: NSSize(width: max(textSize.width + 20, 300), height: max(textSize.height + 20, 100)))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        attributedString.draw(at: NSPoint(x: 10, y: (image.size.height - textSize.height) / 2))
        image.unlockFocus()
        
        imageView?.imageScaling = .scaleProportionallyUpOrDown
        imageView?.imageAlignment = .alignCenter
        imageView?.image = image
        pageLabel?.stringValue = ""
    // スライダーを無効化
    pageSlider?.minValue = 1
    pageSlider?.maxValue = 1
    pageSlider?.integerValue = 1
    pageSlider?.isEnabled = false
    refreshPager()
    }

    // MARK: - シンプルなページ押し出しトランジション
    private func applyTransition(forward: Bool) {
    // トランジションが無効なら適用しない（ユーザー指定優先）
    if !isTransitionEnabled { return }
        guard let layer = imageView?.layer else { return }
        let t = CATransition()
        t.type = .push
        // 読み方向に合わせて左右を反転
        let subtype: CATransitionSubtype
        if isRightToLeftReading {
            // RTL: 進む=fromLeft, 戻る=fromRight
            subtype = forward ? .fromLeft : .fromRight
        } else {
            // LTR: 進む=fromRight, 戻る=fromLeft
            subtype = forward ? .fromRight : .fromLeft
        }
        t.subtype = subtype
        t.duration = 0.25
        t.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    layer.add(t, forKey: "cz_push")
    if let rLayer = rightImageView?.layer {
            // 右側には別インスタンス
            let t2 = CATransition()
            t2.type = .push
            t2.subtype = subtype
            t2.duration = t.duration
            t2.timingFunction = t.timingFunction
            rLayer.add(t2, forKey: "cz_push_r")
        }
    }

    // MARK: - マウスホイールスクロール処理

    private func handleScrollEvent(_ event: NSEvent) -> Bool {
        let currentTime = CACurrentMediaTime()
        let deltaY = event.scrollingDeltaY

        // 横スクロールは無視（縦スクロールのみ処理）
        guard abs(deltaY) > 0.1 else { return false }

        // 連続スクロール防止のクールダウン時間チェック
        if currentTime - lastScrollTime < scrollCooldownInterval {
            return false
        }

        // スクロール量を累積
        scrollAccumulator += deltaY

        // 閾値を超えた場合のみページ送りを実行
        if abs(scrollAccumulator) >= scrollThreshold {
            let shouldNextPage: Bool

            // スクロール方向と読み方向設定でページ送り方向を決定
            if isRightToLeftReading {
                // 右綴じ: 下スクロール(-)=次ページ、上スクロール(+)=前ページ
                shouldNextPage = scrollAccumulator < 0
            } else {
                // 左綴じ: 下スクロール(-)=次ページ、上スクロール(+)=前ページ
                shouldNextPage = scrollAccumulator < 0
            }

            // ページ送り実行
            let didChangePage = performPageNavigation(forward: shouldNextPage)

            if didChangePage {
                // ページ送りが成功した場合のみ累積量をリセット
                scrollAccumulator = 0.0
                lastScrollTime = currentTime
                return true
            }
        }

        return false
    }

    private func performPageNavigation(forward: Bool) -> Bool {
        let isSpreadMode = currentViewMode == .spread

        // スライドショー中の手動操作は一時的に停止・再開
        let wasSlideshow = isSlideshowEnabled
        if wasSlideshow { stopSlideshow() }

        let didChange: Bool
        if forward {
            didChange = imageManager.nextImage(isSpreadMode: isSpreadMode)
            if didChange {
                setViewMode(shouldUseSpreadMode() ? .spread : .single)
                applyTransition(forward: true)
                displayCurrentImage()
                saveReadingPositionToHistory()
            }
        } else {
            didChange = imageManager.previousImage(isSpreadMode: isSpreadMode)
            if didChange {
                setViewMode(shouldUseSpreadMode() ? .spread : .single)
                applyTransition(forward: false)
                displayCurrentImage()
                saveReadingPositionToHistory()
            }
        }

        // スライドショーが動いていた場合は再開
        if wasSlideshow && didChange {
            startSlideshow()
        }

        // サムネイル選択を現在ページに同期
        if didChange {
            syncThumbnailSelection()
        }

        return didChange
    }

    // トランジションのON/OFF切替
    @objc private func toggleTransition(_ sender: NSMenuItem) {
        applyTransitionEnabled(!isTransitionEnabled)
    }

    // 保存フレーム読み出し/保存（共有UserDefaultsに統一）
    private func loadRestoreWindowFrameEnabled() -> Bool {
        return CZUserDefaults.shared.object(forKey: CZSettingsKeys.restoreWindowFrameEnabled) as? Bool ?? true
    }
    private func loadSavedWindowFrame() -> NSRect? {
        guard let s = CZUserDefaults.shared.string(forKey: CZSettingsKeys.savedWindowFrameString) else { return nil }
        return NSRectFromString(s)
    }
    private func saveWindowFrameIfEnabled() {
        guard (CZUserDefaults.shared.object(forKey: CZSettingsKeys.restoreWindowFrameEnabled) as? Bool ?? true), let win = view.window else { return }
        CZUserDefaults.shared.set(NSStringFromRect(win.frame), forKey: CZSettingsKeys.savedWindowFrameString)
    }

    private func setImageSafely(_ image: NSImage?, toImageView imageView: NSImageView?) {
        guard let iv = imageView else { return }
        // スケーリングのみ固定。アラインメントはモード切替で設定したものを維持する
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.image = image
    }

    @discardableResult
    private func setPrerenderedLayer(_ layer: CALayer?, toImageView imageView: NSImageView?, fallbackImage: NSImage?, side: SpreadPageSide? = nil) -> Bool {
        guard let imageView, let hostLayer = imageView.layer else {
            setImageSafely(fallbackImage, toImageView: imageView)
            return false
        }
        guard let layer else {
            setImageSafely(fallbackImage, toImageView: imageView)
            return false
        }
        imageView.layoutSubtreeIfNeeded()
        view.layoutSubtreeIfNeeded()
        guard !hostLayer.bounds.isEmpty else {
            setImageSafely(fallbackImage, toImageView: imageView)
            return false
        }
        guard let prerenderedContents = layer.contents else {
            setImageSafely(fallbackImage, toImageView: imageView)
            return false
        }

        hostLayer.sublayers?.filter { $0.name == "cz_prerendered" }.forEach { $0.removeFromSuperlayer() }
        // フォールバック画像は残したまま上にレイヤーを重ねる（失敗時の黒画面防止）
        setImageSafely(fallbackImage, toImageView: imageView)

        let displayLayer = CALayer()
        displayLayer.name = "cz_prerendered"
        displayLayer.contents = prerenderedContents
        displayLayer.contentsGravity = .resizeAspect
        displayLayer.contentsScale = max(hostLayer.contentsScale, view.window?.backingScaleFactor ?? 1.0)
        displayLayer.minificationFilter = .trilinear
        displayLayer.magnificationFilter = .linear

        let sourceSize = layer.bounds.size
        if let side, sourceSize.width > 0, sourceSize.height > 0 {
            // 見開きはNSImageViewのalignRight/alignLeftと同じくノド側へ寄せる
            // （.resizeAspectのままframe=boundsにすると各半分の中央に置かれ、中心に隙間が生じる）
            let aspect = sourceSize.width / sourceSize.height
            displayLayer.frame = anchoredAspectFitFrame(aspect: aspect, in: hostLayer.bounds, side: side)
            displayLayer.setValue(Double(aspect), forKey: Self.prerenderedLayerAspectKey)
            displayLayer.setValue(side == .left, forKey: Self.prerenderedLayerIsLeftKey)
        } else {
            displayLayer.frame = hostLayer.bounds
            displayLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        }
        hostLayer.addSublayer(displayLayer)
        return true
    }

    private static let prerenderedLayerAspectKey = "czPageAspect"
    private static let prerenderedLayerIsLeftKey = "czPageIsLeft"

    /// hostLayer内でアスペクト比を保ったままノド側（左ページ=右端、右ページ=左端）へ寄せた枠を返す
    private func anchoredAspectFitFrame(aspect: CGFloat, in bounds: CGRect, side: SpreadPageSide) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return bounds }
        var size = CGSize(width: bounds.width, height: bounds.width / aspect)
        if size.height > bounds.height {
            size = CGSize(width: bounds.height * aspect, height: bounds.height)
        }
        let originY = bounds.minY + (bounds.height - size.height) / 2
        let originX: CGFloat
        switch side {
        case .left:
            originX = bounds.maxX - size.width
        case .right:
            originX = bounds.minX
        }
        return CGRect(x: originX, y: originY, width: size.width, height: size.height)
    }

    /// ビューサイズ変更後に見開きプリレンダーレイヤーをノド側へ再配置する
    private func realignSpreadPrerenderedLayers() {
        for hostView in [imageView, rightImageView] {
            guard let hostLayer = hostView?.layer else { continue }
            for sublayer in hostLayer.sublayers ?? [] where sublayer.name == "cz_prerendered" {
                guard let aspectValue = sublayer.value(forKey: Self.prerenderedLayerAspectKey) as? Double,
                      let isLeft = sublayer.value(forKey: Self.prerenderedLayerIsLeftKey) as? Bool else { continue }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                sublayer.frame = anchoredAspectFitFrame(
                    aspect: CGFloat(aspectValue),
                    in: hostLayer.bounds,
                    side: isLeft ? .left : .right
                )
                CATransaction.commit()
            }
        }
    }

    private func clearPrerenderedLayers() {
        imageView?.layer?.sublayers?.filter { $0.name == "cz_prerendered" }.forEach { $0.removeFromSuperlayer() }
        rightImageView?.layer?.sublayers?.filter { $0.name == "cz_prerendered" }.forEach { $0.removeFromSuperlayer() }
    }

    // スライダー上のクリックなら、クリック位置に即時ジャンプしてアクションを発火（イベント自体は通す）
    private func immediatelyJumpSliderIfNeeded(atViewPoint pointInView: NSPoint) {
        guard let slider = pageSlider, slider.isHidden == false, slider.isEnabled else { return }
        // クリックがスライダー（または子孫）上か確認
        guard isPointInsidePageSlider(pointInView) else { return }
        // ビュー座標→スライダー座標
        let local = slider.convert(pointInView, from: view)
        guard slider.bounds.width > 0 else { return }
        var ratio = max(0, min(1, Double(local.x / slider.bounds.width)))
        // RTL時は比率を反転（左端=最大値）
        if isRightToLeftReading { ratio = 1 - ratio }
        let newValue = slider.minValue + (slider.maxValue - slider.minValue) * ratio
        // ノブを即時移動（ページは整数なので丸め）
        let rounded = Double(Int(newValue.rounded()))
        if slider.doubleValue != rounded {
            slider.doubleValue = rounded
            // 直接アクションを呼ぶ（target/actionに委ねる）
            if let action = slider.action { NSApp.sendAction(action, to: slider.target, from: slider) }
        }
    }

    // ビュー座標が pageSlider（またはそのサブビュー階層）上かを判定
    private func isPointInsidePageSlider(_ pointInView: NSPoint) -> Bool {
        guard let slider = pageSlider, let hit = view.hitTest(pointInView) else { return false }
        var v: NSView? = hit
        while let cur = v {
            if cur === slider { return true }
            v = cur.superview
        }
        return false
    }

    // 表示コンテキスト（主に幅）に応じてスライダーの可視性を切り替える
    private func updateSliderVisibilityForContext() {
        guard pageSlider != nil else { return }
        let shouldHide = shouldHideSliderForContext()
        setSliderVisible(!shouldHide)
    }

    private func shouldHideSliderForContext() -> Bool {
        // Finderカラム内かどうかの判定が困難なため、常にスライダーを表示
        return false
    }

    private func setSliderVisible(_ visible: Bool) {
        guard let slider = pageSlider else { return }
        // 旧UIスライダーは画像に重ねる進捗バーへ役割を移行済み。値モデルとしてのみ保持し、常時非表示にする。
        slider.isHidden = true
        slider.isEnabled = visible && imageManager.getImageCount() > 1
        applySliderLayoutDirection()
    }

    // スライダー（値モデル）と進捗バーのハイライト向きを読書方向に合わせる
    private func applySliderLayoutDirection() {
        guard let slider = pageSlider else { return }
        if #available(macOS 10.12, *) {
            slider.userInterfaceLayoutDirection = isRightToLeftReading ? .rightToLeft : .leftToRight
        }
        pageProgressBar?.isRightToLeftReading = isRightToLeftReading
    }

    // スライダーの最小/最大と有効状態を更新
    private func updateSliderLimits() {
        let count = imageManager.getImageCount()
        if count > 0 {
            pageSlider?.minValue = 1
            pageSlider?.maxValue = Double(count)
            // 現在ページに同期（方向反転に対応）
            syncSliderToCurrentPage()
            pageSlider?.isEnabled = true
        } else {
            pageSlider?.minValue = 1
            pageSlider?.maxValue = 1
            pageSlider?.integerValue = 1
            pageSlider?.isEnabled = false
            refreshPager()
        }
    }

    // スライダー変更時にページ移動
    @IBAction func pageSliderChanged(_ sender: NSSlider) {
        // スライドショー中のスライダー操作は一時的に停止・再開
        let wasSlideshow = isSlideshowEnabled
        if wasSlideshow { stopSlideshow() }
        
        // スライダーの見た目方向はRTLに合わせているため、内部値は反転しない
        let page = sender.integerValue
        if imageManager.goToPage(Int(page)) {
            displayCurrentImage()
            // 履歴を自動保存
            saveReadingPositionToHistory()
        }

        // スライドショーが有効だった場合は再開
        if wasSlideshow { startSlideshow() }

        // 内蔵ビューアのキーボードフォーカス復帰のため通知を送信
        DistributedNotificationCenter.default().post(
            name: CZDistributedNotifications.sliderOperationCompleted,
            object: nil
        )
    }

    /// サムネイルクリック時のページ遷移（サムネイル再選択をスキップして応答性を向上）
    private func moveToPageFromThumbnail(_ page: Int) {
        let wasSlideshow = isSlideshowEnabled
        if wasSlideshow { stopSlideshow() }

        skipThumbnailSyncOnce = !shouldUseSpreadMode()
        if imageManager.goToPage(page) {
            displayCurrentImage()
            saveReadingPositionToHistory()
        }

        if wasSlideshow { startSlideshow() }

        DistributedNotificationCenter.default().post(
            name: CZDistributedNotifications.sliderOperationCompleted,
            object: nil
        )
    }

    /// サムネイル選択などをスライダー操作経路へ統一してページ移動する
    private func moveToPageViaSlider(_ page: Int) {
        guard let slider = pageSlider else {
            if imageManager.goToPage(page) {
                displayCurrentImage()
                saveReadingPositionToHistory()
            }
            return
        }

        slider.integerValue = page
        pageSliderChanged(slider)
    }

    private func currentThumbnailSelectionIndices() -> [Int] {
        if currentViewMode == .spread {
            let pair = imageManager.getCurrentSpreadPairIndices(isRightToLeft: isRightToLeftReading)
            return [pair.left, pair.right].compactMap { $0 }
        }
        return [imageManager.currentPageIndex]
    }

    private func syncThumbnailSelection(scrollToVisible: Bool = true) {
        thumbnailStripView?.selectItems(
            at: currentThumbnailSelectionIndices(),
            primaryRealIndex: imageManager.currentPageIndex,
            scrollToVisible: scrollToVisible
        )
    }

    // 現在ページをスライダー位置へ反映（方向反転対応）
    private func syncSliderToCurrentPage(skipThumbnailSync: Bool = false) {
        guard let slider = pageSlider else { return }
        // 内部値はそのまま同期（見た目の方向はUIレベルで反映）
        let current = imageManager.getCurrentPageNumber()
        slider.integerValue = current
        if !skipThumbnailSync {
            syncThumbnailSelection()
        }
        refreshPager()
    }

    /// 画像に重ねる進捗バーの塗りつぶし・ページ番号を最新の状態へ更新する
    private func refreshPager() {
        guard let bar = pageProgressBar else { return }
        let total = imageManager.getImageCount()
        let current = imageManager.getCurrentPageNumber()
        bar.update(currentPage: current, totalPages: max(total, 1))
        bar.isEnabled = total > 1
    }

    // Quick Look ホストに対して、縦方向いっぱいの希望サイズをヒントとして提示
    //
    // preferredContentSize がホストの実際の割り当てサイズより小さいと、ホスト（自前の
    // QLPreviewView / システムのQuick Lookパネルいずれも）はリモートコンテンツをそのヒント
    // サイズで中央配置し、余白を自前で描画する。この余白はホスト側の領域であり拡張からは
    // 一切操作できない（マウスカーソル変更・クリックページ送りが背景で反応しない原因）。
    // ホストがすでにより大きな領域を与えている場合はそれを下回らないよう、常に
    // 「理想サイズ」と「実際に与えられているサイズ」の大きい方を報告し、ホストが余白を
    // 保持し続けないようにする。
    private func updatePreferredContentSizeIfNeeded() {
        let idealSize = idealPreferredContentSize()
        let actualSize = NSSize(
            width: max(view.bounds.width, view.window?.frame.width ?? 0),
            height: max(view.bounds.height, view.window?.frame.height ?? 0)
        )
        let size = NSSize(
            width: max(idealSize.width, actualSize.width),
            height: max(idealSize.height, actualSize.height)
        )
        guard size.width > 0, size.height > 0 else { return }
        if preferredContentSize != size { preferredContentSize = size }
    }

    /// 初回表示時などにホストへ提示する理想サイズ（保存フレーム優先、なければ画像アスペクト基準の縦いっぱい）
    private func idealPreferredContentSize() -> NSSize {
        // 1) 復元が有効で保存サイズがある場合は、それを優先して返す
        if loadRestoreWindowFrameEnabled(), let saved = loadSavedWindowFrame() {
            return saved.size
        }
        // 2) 未保存/復元無効のときは、従来通り縦方向いっぱい
        guard let screen = view.window?.screen ?? NSScreen.main else { return preferredContentSize }
        let visible = screen.visibleFrame.size
        guard visible.height > 0 else { return preferredContentSize }
        let aspect = currentImageAspect ?? (view.bounds.height > 0 ? max(view.bounds.width, 1) / view.bounds.height : 1.0)
        // まず高さを画面の可視領域いっぱいに
        var targetHeight = visible.height
        var targetWidth = aspect * targetHeight
        // 横幅が画面を超える場合は横に合わせて縮小
        if targetWidth > visible.width {
            targetWidth = visible.width
            targetHeight = max(1, targetWidth / max(aspect, 0.0001))
        }
        return NSSize(width: targetWidth, height: targetHeight)
    }



    private func convertEventPointToView(_ event: NSEvent) -> NSPoint? {
        // 1) まずスクリーン座標へ
        let screenPoint: NSPoint
        if let win = event.window {
            screenPoint = win.convertPoint(toScreen: event.locationInWindow)
        } else {
            // ローカルモニタでwindowがnilな場合は現在のマウス座標を使用
            screenPoint = NSEvent.mouseLocation
        }
        // 2) プレビューのウィンドウ座標へ
        guard let myWin = view.window else { return nil }
        let windowPoint = myWin.convertPoint(fromScreen: screenPoint)
        // 3) ビュー座標へ
        let viewPoint = view.convert(windowPoint, from: nil)
        return viewPoint
    }

    /// より堅牢な座標変換（フォールバック機能付き）
    private func convertEventPointToViewRobust(_ event: NSEvent) -> NSPoint? {
        // 基本的な座標変換を試行
        if let basicPoint = convertEventPointToView(event) {
            return basicPoint
        }
        
        // フォールバック1: NSEvent.mouseLocation を直接使用
        guard let myWin = view.window else { 
            verboseLog("[DEBUG] Fallback failed: view.window is nil")
            return nil 
        }
        
        let screenPoint = NSEvent.mouseLocation
        let windowPoint = myWin.convertPoint(fromScreen: screenPoint)
        let viewPoint = view.convert(windowPoint, from: nil)
        
        verboseLog("[DEBUG] Fallback coordinate conversion: screen=(%f,%f) -> window=(%f,%f) -> view=(%f,%f)", 
              screenPoint.x, screenPoint.y, windowPoint.x, windowPoint.y, viewPoint.x, viewPoint.y)
        
        return viewPoint
    }

    // 指定ビュー座標が「通過させるべきNSControl」上かを判定（imageView配下は除外して吸収対象にする）
    private func isPointInsidePassThroughControl(_ pointInView: NSPoint) -> Bool {
        // サムネイルストリップ領域のクリックはそのまま通す（ページ移動を発生させない）
        if let strip = thumbnailStripView, strip.frame.contains(pointInView) { return true }
        guard let hit = view.hitTest(pointInView) else { return false }
        var v: NSView? = hit
        while let cur = v {
            // 左右両方のImageViewをクリック対象から除外（ページ移動処理の対象にする）
            if let iv = self.imageView, cur === iv { return false }
            if let riv = self.rightImageView, cur === riv { return false }
            if cur is NSControl { return true }
            v = cur.superview
        }
        return false
    }

    private func isThumbnailStripFirstResponderActive() -> Bool {
        guard let strip = thumbnailStripView,
              let responder = view.window?.firstResponder else { return false }
        guard let responderView = responder as? NSView else { return false }

        var currentView: NSView? = responderView
        while let viewInChain = currentView {
            if viewInChain === strip.collectionView || viewInChain === strip {
                return true
            }
            currentView = viewInChain.superview
        }
        return false
    }
    
    private func updatePageLabel() {
        let currentPage = imageManager.getCurrentPageNumber()
        let totalPages = imageManager.getImageCount()
        pageLabel?.stringValue = "\(currentPage) / \(totalPages)"
    }
    
    // キーボード入力はQuick Lookホストに委ねる（本拡張では未処理）
    
}

// MARK: - パフォーマンス最適化
private extension PreviewViewController {
    /// ImageManagerに現在のウィンドウサイズを設定して最適化を有効にする
    ///
    /// - Parameter useScreenFallback: `true` の場合、`view.window` が未確定でも
    ///   `view.bounds` / `NSScreen.main` から推定したサイズでバケットを確定させる
    ///   （`preparePreviewOfFile` 時点での先渡し用）。
    @discardableResult
    func updateImageManagerDisplaySize(useScreenFallback: Bool = false) -> Bool {
        let contentSize = view.bounds.size
        let windowSize = view.window?.frame.size ?? .zero
        let backingScaleFactor = view.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 1.0

        var targetPointSize = NSSize(
            width: max(contentSize.width, windowSize.width),
            height: max(contentSize.height, windowSize.height)
        )

        if targetPointSize.width <= 0 || targetPointSize.height <= 0 {
            guard useScreenFallback, let screenSize = NSScreen.main?.frame.size else { return false }
            targetPointSize = screenSize
        }

        let maxSize: CGFloat = 3840
        let limitedSize = NSSize(
            width: min(targetPointSize.width, maxSize),
            height: min(targetPointSize.height, maxSize)
        )

        let didBucketChange = imageManager.setTargetDisplaySize(limitedSize, backingScaleFactor: backingScaleFactor)

        NSLog(
            "[Performance] Updated display size: points=%dx%d scale=%f",
            Int(limitedSize.width),
            Int(limitedSize.height),
            backingScaleFactor
        )
        return didBucketChange
    }
}

// MARK: - 読書履歴
private extension PreviewViewController {
    func restoreReadingPositionFromHistory() {
        guard !currentZipFilename.isEmpty else { return }

        if let history = readingHistoryManager.loadReadingPosition(filename: currentZipFilename) {
            NSLog("[ReadingHistory] Restoring position for %@: page %d, viewMode %@, offset %d, rtl %@", currentZipFilename, history.page, history.viewMode, history.spreadPairOffset, history.isRightToLeftReading?.description ?? "nil")
            _ = imageManager.goToPage(history.page)
            imageManager.setSpreadPairOffset(history.spreadPairOffset)

            if let rtl = history.isRightToLeftReading {
                isRightToLeftReading = rtl
                didRestoreRTLFromHistory = true
                applySliderLayoutDirection()
                syncSliderToCurrentPage()
                updateContextMenuStates()
            }

            if let restored = ViewModePreference(rawValue: history.viewMode) {
                userPreferredViewMode = restored
                didRestoreViewModeFromHistory = true
                if imageManager.hasImages() { displayCurrentImage() }
                updateContextMenuStates()
            }

            NSLog("[ReadingHistory] Position restored successfully")
        } else {
            NSLog("[ReadingHistory] No history found for %@", currentZipFilename)
        }

    }

    func saveReadingPositionToHistory() {
        guard !currentZipFilename.isEmpty, imageManager.hasImages() else { return }

        let currentPage = imageManager.getCurrentPageNumber()
        let currentViewMode = userPreferredViewMode.rawValue
        let currentOffset = imageManager.getSpreadPairOffset()

        readingHistoryManager.saveReadingPosition(
            filename: currentZipFilename,
            page: currentPage,
            viewMode: currentViewMode,
            spreadPairOffset: currentOffset,
            isRightToLeftReading: isRightToLeftReading
        )
    }
}

// MARK: - サムネイルストリップ高さの永続化
private extension PreviewViewController {
    func loadThumbnailStripHeight() -> CGFloat {
        let saved = CZUserDefaults.shared.double(forKey: CZSettingsKeys.thumbnailStripHeight)
        return saved > 0 ? saved : 88
    }

    func saveThumbnailStripHeight(_ height: CGFloat) {
        CZUserDefaults.shared.set(height, forKey: CZSettingsKeys.thumbnailStripHeight)
    }
}

// MARK: - カーソル管理

/// プレビュー画像エリアに左右矢印カーソルを表示するための透明オーバーレイビュー。
private final class PreviewCursorAreaView: NSView {
    override var acceptsFirstResponder: Bool { false }

    /// マウス移動時に、自ビューのローカル座標を通知する（進捗バーの下部バンド検知に使用）
    var onMouseMoved: ((NSPoint) -> Void)?
    /// カーソルが画像領域から離れた際に通知する（進捗バーの即時消灯に使用）
    var onMouseExited: (() -> Void)?

    // カーソル画像を初回のみ生成（フォールバックあり）
    // ホットスポット: 32×32pt 画像の矢印先端を想定。実際の画像に合わせて調整してください。
    private static let cursorLeft: NSCursor = {
        let bundle = Bundle(for: PreviewCursorAreaView.self)
        if let img = bundle.image(forResource: "cursor-left") {
            return NSCursor(image: img, hotSpot: NSPoint(x: 2, y: 16))
        }
        return .resizeLeft
    }()

    private static let cursorRight: NSCursor = {
        let bundle = Bundle(for: PreviewCursorAreaView.self)
        if let img = bundle.image(forResource: "cursor-right") {
            return NSCursor(image: img, hotSpot: NSPoint(x: 29, y: 16))
        }
        return .resizeRight
    }()

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }

    override func mouseEntered(with event: NSEvent) {
        updateCursor(for: event)
        onMouseMoved?(convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(for: event)
        onMouseMoved?(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
        onMouseExited?()
    }

    // ウィンドウ内でのカーソル矩形（mouseMoved が届かないケースの補完）
    override func resetCursorRects() {
        let half = bounds.width / 2
        addCursorRect(NSRect(x: 0, y: 0, width: half, height: bounds.height), cursor: Self.cursorLeft)
        addCursorRect(NSRect(x: half, y: 0, width: bounds.width - half, height: bounds.height), cursor: Self.cursorRight)
    }

    private func updateCursor(for event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        (x < bounds.width / 2 ? Self.cursorLeft : Self.cursorRight).set()
    }
}
