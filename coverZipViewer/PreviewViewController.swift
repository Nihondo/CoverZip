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

// MARK: - Preview View Controller

class PreviewViewController: NSViewController, QLPreviewingController {
    
    @IBOutlet weak var imageView: NSImageView!
    @IBOutlet weak var rightImageView: NSImageView!
    @IBOutlet weak var pageLabel: NSTextField!
    @IBOutlet weak var pageSlider: NSSlider!
    
    private var imageManager = ImageManager()
    private var readingHistoryManager = ReadingHistoryManager.shared
    private var currentZipFilename: String = ""
    private var mouseMonitors: [Any] = []
    private var pendingSingleClick: DispatchWorkItem?
    private var currentImageAspect: CGFloat?
    // スライダー表示/非表示のための制約管理
    private var sliderConstraints: [NSLayoutConstraint] = []
    private var directLabelTopConstraint: NSLayoutConstraint?
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
    private var distributedObservers: [NSObjectProtocol] = []
    // セッション中にユーザーがウィンドウをリサイズしたか
    private var hasUserResizedWindow: Bool = false
    // 履歴から綴じ方向を復元済みか（既定で上書きしないためのフラグ）
    private var didRestoreRTLFromHistory: Bool = false
    // 履歴から表示モードを復元済みか（既定で上書きしないためのフラグ）
    private var didRestoreViewModeFromHistory: Bool = false
    private var didLogHostWindowInfo: Bool = false
    // 読み込みインジケータ
    private var loadingIndicator: NSProgressIndicator?
    // 全件読み込み完了後に適用する予定のページ（ヒューリスティクス先頭表示→履歴ページへ移動のため）
    private var pendingRestorePage: Int?
    
    // 表示モード
    enum ViewMode {
        case single
        case spread
    }
    private var currentViewMode: ViewMode = .single
    private var didApplyInitialViewMode = false
    
    // ユーザー設定管理
    private var userPreferredViewMode: PrefViewMode = .auto
    private var isAutoMode: Bool {
        return userPreferredViewMode == .auto
    }

    // App Group UserDefaults ヘルパー（共有定義に統一）
    private func sharedDefaults() -> UserDefaults { UserDefaults(suiteName: CZAppGroup.identifier) ?? .standard }
    private func loadIsRTL() -> Bool { sharedDefaults().object(forKey: CZSettingsKeys.isRightToLeftReading) as? Bool ?? true }
    private func loadSliderThreshold() -> CGFloat { CGFloat(sharedDefaults().object(forKey: CZSettingsKeys.sliderVisibilityWidthThreshold) as? Double ?? 600.0) }
    private func loadAlwaysSinglePageForCover() -> Bool { sharedDefaults().object(forKey: CZSettingsKeys.alwaysSinglePageForCover) as? Bool ?? true }
    private enum PrefViewMode: String { case auto, single, spread }
    private func loadDefaultViewMode() -> PrefViewMode { PrefViewMode(rawValue: sharedDefaults().string(forKey: CZSettingsKeys.defaultViewMode) ?? "auto") ?? .auto }
    private func loadSlideshowInterval() -> Double { sharedDefaults().object(forKey: CZSettingsKeys.slideshowInterval) as? Double ?? 3.0 }
    private func loadTransitionEnabled() -> Bool { sharedDefaults().object(forKey: CZSettingsKeys.pageTransitionEnabled) as? Bool ?? true }
    
    override var nibName: NSNib.Name? {
        return NSNib.Name("PreviewViewController")
    }

    override func loadView() {
        super.loadView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    // UserDefaultsから設定をロード
    isRightToLeftReading = loadIsRTL()
    sliderVisibilityWidthThreshold = loadSliderThreshold()
    // ユーザー設定の表示モードを初期ロード
    userPreferredViewMode = loadDefaultViewMode()
    // ページ送りアニメの初期状態を共有設定からロード
    isTransitionEnabled = loadTransitionEnabled()
    NSLog("[DEBUG] Initial userPreferredViewMode loaded: %@", userPreferredViewMode.rawValue)
        setupUI()
        setupGestureRecognizers()
        // 初期状態ではインジケータは表示しない
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // マウスイベントをホスト（Finder）へ渡さないためにローカルモニタで吸収（down/up 両方）
        if let down = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] event -> NSEvent? in
            guard let self else { return event }
            if self.view.window != nil {
                // 座標変換に失敗したら安全側でイベントを通す
                guard let p = self.convertEventPointToView(event) else { return event }
                // 自ビュー領域内の時は吸収（NSControl上は通す）
                guard self.view.bounds.contains(p) else { return event }
                // Control-クリックはコンテキストメニューを表示
                if event.modifierFlags.contains(.control) {
                    let menu = self.makeContextMenu()
                    menu.popUp(positioning: nil, at: p, in: self.view)
                    return nil
                }
                // スライダーなどのNSControl（やそのサブビュー）上のクリックは通す（ただしimageView配下は除外）
                if self.isPointInsidePassThroughControl(p) {
                    // A案: スライダートラック上クリック時は即時に値を反映してアクション実行（イベントは通す）
                    self.immediatelyJumpSliderIfNeeded(atViewPoint: p)
                    NSLog("[DEBUG] Mouse down passed through to control")
                    return event
                }
                // 画像エリアのクリックは吸収（ダブルクリック抑止）
                self.pendingSingleClick?.cancel()
                self.pendingSingleClick = nil
                return nil
            }
            return event
        }) {
            mouseMonitors.append(down)
        }
        // 右クリックで拡張のメニューを確実に表示（QLPreviewView 埋め込みでも有効化）
        if let rdown = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown, handler: { [weak self] event -> NSEvent? in
            guard let self else { return event }
            guard self.view.window != nil, let p = self.convertEventPointToView(event), self.view.bounds.contains(p) else { return event }
            let menu = self.makeContextMenu()
            menu.popUp(positioning: nil, at: p, in: self.view)
            return nil
        }) {
            mouseMonitors.append(rdown)
        }
        if let up = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] event -> NSEvent? in
            guard let self else { return event }
            if self.view.window != nil {
                // 座標変換に失敗したら安全側でイベントを通す
                guard let vPoint = self.convertEventPointToView(event) else { return event }
                // 自ビュー領域外はホストに渡す
                guard self.view.bounds.contains(vPoint) else { return event }
                // スライダーなどのNSControl（やそのサブビュー）上のクリックは通す（ただしimageView配下は除外）
                if self.isPointInsidePassThroughControl(vPoint) { 
                    NSLog("[DEBUG] Click passed through to control")
                    return event 
                }
                // マウスアップでページめくり処理を実行（画像エリアのみ）
                let bounds = self.view.bounds
                let isLeftHalf = vPoint.x < bounds.width / 2
                let isSpreadMode = self.currentViewMode == .spread
                
                NSLog("[DEBUG] Click detected at (%f, %f) in bounds %@, isLeftHalf=%d, isSpreadMode=%d", vPoint.x, vPoint.y, NSStringFromRect(bounds), isLeftHalf, isSpreadMode)
                
                // スライドショー中の手動操作は一時的に停止・再開
                let wasSlideshow = self.isSlideshowEnabled
                if wasSlideshow { self.stopSlideshow() }
                
                if self.isRightToLeftReading {
                    // 反転: 左=進む、右=戻る
                    if isLeftHalf {
                        NSLog("[DEBUG] RTL: Left click - Next page")
                        if self.imageManager.nextImage(isSpreadMode: isSpreadMode) {
                            // ViewModeを決定してからアニメ適用
                            self.setViewMode(self.shouldUseSpreadMode() ? .spread : .single)
                            self.applyTransition(forward: true)
                            self.displayCurrentImage()
                            // 履歴を自動保存
                            self.saveReadingPositionToHistory()
                        }
                    } else {
                        NSLog("[DEBUG] RTL: Right click - Previous page")
                        if self.imageManager.previousImage(isSpreadMode: isSpreadMode) {
                            self.setViewMode(self.shouldUseSpreadMode() ? .spread : .single)
                            self.applyTransition(forward: false)
                            self.displayCurrentImage()
                            // 履歴を自動保存
                            self.saveReadingPositionToHistory()
                        }
                    }
                } else {
                    // 通常: 左=戻る、右=進む
                    if isLeftHalf {
                        NSLog("[DEBUG] LTR: Left click - Previous page")
                        if self.imageManager.previousImage(isSpreadMode: isSpreadMode) {
                            self.setViewMode(self.shouldUseSpreadMode() ? .spread : .single)
                            self.applyTransition(forward: false)
                            self.displayCurrentImage()
                            // 履歴を自動保存
                            self.saveReadingPositionToHistory()
                        }
                    } else {
                        NSLog("[DEBUG] LTR: Right click - Next page")
                        if self.imageManager.nextImage(isSpreadMode: isSpreadMode) {
                            self.setViewMode(self.shouldUseSpreadMode() ? .spread : .single)
                            self.applyTransition(forward: true)
                            self.displayCurrentImage()
                            // 履歴を自動保存
                            self.saveReadingPositionToHistory()
                        }
                    }
                }
                
                // スライドショーが有効だった場合は再開
                if wasSlideshow { self.startSlideshow() }
                return nil // ホストには渡さない
            }
            return event
        }) {
            mouseMonitors.append(up)
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        
        // 読書履歴を保存
        saveReadingPositionToHistory()
        
        // ユーザーがこのセッションでリサイズした場合のみ最終フレームを保存
        if hasUserResizedWindow { saveWindowFrameIfEnabled() }
        // 通知クリーンアップ
        for o in windowObservers { NotificationCenter.default.removeObserver(o) }
        windowObservers.removeAll()
        for d in distributedObservers { DistributedNotificationCenter.default().removeObserver(d) }
        distributedObservers.removeAll()
        for m in mouseMonitors { NSEvent.removeMonitor(m) }
        mouseMonitors.removeAll()
        pendingSingleClick?.cancel()
        pendingSingleClick = nil
        // スライドショーのクリーンアップ
        stopSlideshow()
        // ローディングインジケータ停止
        hideLoadingIndicator()
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        // Quick LookではFirst Responderを取得しない
        // レイアウト完了後のサイズで初回画像を再フィット
        // 設定の変更を反映
        let newRTL = loadIsRTL()
        if !didRestoreRTLFromHistory && newRTL != isRightToLeftReading {
            isRightToLeftReading = newRTL
            applySliderLayoutDirection()
            syncSliderToCurrentPage()
        }
        let newThreshold = loadSliderThreshold()
        if newThreshold != sliderVisibilityWidthThreshold { sliderVisibilityWidthThreshold = newThreshold; updateSliderVisibilityForContext() }
        // ページ送りアニメ設定の変更を反映
        let newTransition = loadTransitionEnabled()
        if newTransition != isTransitionEnabled { isTransitionEnabled = newTransition }
        
        // デフォルト表示モード設定の変更をチェック
        let newViewMode = loadDefaultViewMode()
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
            
            // 画像リストの全読み込み完了通知（初回は高速表示→後で全件に差し替え）
            let reloadObserver = NotificationCenter.default.addObserver(forName: .czImageManagerDidLoadAll, object: imageManager, queue: .main) { [weak self] _ in
                guard let self else { return }
                // 履歴ページが保留されていれば、ここで反映
                if let target = self.pendingRestorePage {
                    _ = self.imageManager.goToPage(target)
                    self.pendingRestorePage = nil
                }
                self.updateSliderLimits()
                self.syncSliderToCurrentPage()
                self.displayCurrentImage()
                self.hideLoadingIndicator()
            }
            windowObservers.append(reloadObserver)
        }
        
        // 初期表示サイズを設定
        updateImageManagerDisplaySize()

        // アプリ側の設定変更を反映（Distributed Notification 経由）
        let distObs = DistributedNotificationCenter.default().addObserver(forName: CZDistributedNotifications.settingsChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            // 最新設定を共有UserDefaultsから再取得
            let newRTL = self.loadIsRTL()
            if !self.didRestoreRTLFromHistory && newRTL != self.isRightToLeftReading {
                self.isRightToLeftReading = newRTL
                self.applySliderLayoutDirection()
                self.syncSliderToCurrentPage()
            }
            let newTransition = self.loadTransitionEnabled()
            if newTransition != self.isTransitionEnabled { self.isTransitionEnabled = newTransition }
            let newViewMode = self.loadDefaultViewMode()
            if !self.didRestoreViewModeFromHistory && newViewMode != self.userPreferredViewMode {
                self.userPreferredViewMode = newViewMode
            }
            // 表示更新
            if self.imageManager.hasImages() {
                self.displayCurrentImage()
            }
            // メニュー状態を更新
            self.updateContextMenuStates()
        }
        distributedObservers.append(distObs)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // 自動リサイズ機能を使用するため、手動でのリサイズ処理は不要
        // レイアウト変化に応じてスライダーの可視性を見直す
        updateSliderVisibilityForContext()
        // アスペクト比変更に応じて表示モードを再評価（自動モードのみ）
        if imageManager.hasImages() {
            if isAutoMode {
                // 自動モード：レイアウト変更に応じてモードを再評価
                displayCurrentImage()
            } else {
                // 固定モード：表示更新のみ（モード変更なし）
                updateImageDisplayOnly()
            }
        }
    }
    

    /*
    func preparePreviewOfSearchableItem(identifier: String, queryString: String?) async throws {
        // Implement this method and set QLSupportsSearchableItems to YES in the Info.plist of the extension if you support CoreSpotlight.

        // Perform any setup necessary in order to prepare the view.
        // Quick Look will display a loading spinner until this returns.
    }
    */

    func preparePreviewOfFile(at url: URL) async throws {
        // 新しいファイルが読み込まれる際にスライドショーをリセット
        stopSlideshow()
        isSlideshowEnabled = false
        
    // ファイル名を保存（履歴管理用）
    currentZipFilename = url.lastPathComponent
        
    // まずはグローバル設定の既定を適用（履歴があれば後で上書き）
    didRestoreRTLFromHistory = false
    isRightToLeftReading = loadIsRTL()
    // 表示モードも既定から開始（履歴があれば後で上書き）
    didRestoreViewModeFromHistory = false
    userPreferredViewMode = loadDefaultViewMode()
    // 新規ファイルごとに初期適用フラグをリセット
    didApplyInitialViewMode = false
        
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
            }
        } else {
            // 画像が見つからない場合の処理
            await MainActor.run {
                displayNoImagesMessage()
            }
        }
    }

    // MARK: - Loading Indicator
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
        if imageManager.isLoadingAll {
            showLoadingIndicator()
        } else {
            hideLoadingIndicator()
        }
    }
    
    // MARK: - UI Setup
    
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

        // 制約の再構成（スライダー表示/非表示を切り替え可能に）
        if let imageView, let pageLabel, let slider = pageSlider {
            // 既存の imageView と pageLabel の間の縦方向制約を解除
            let toRemove = view.constraints.filter { c in
                let f = c.firstItem as AnyObject?
                let s = c.secondItem as AnyObject?
                return (f === pageLabel && c.firstAttribute == .top && s === imageView && c.secondAttribute == .bottom)
                    || (f === imageView && c.firstAttribute == .bottom && s === pageLabel && c.secondAttribute == .top)
            }
            NSLayoutConstraint.deactivate(toRemove)

            // スライダー経由の制約を作成（保持）
            sliderConstraints = [
                slider.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 8),
                pageLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 6),
                slider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
                slider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12)
            ]
            // スライダーを使わず直接 label を imageView に接続する制約（保持、初期は非アクティブ）
            directLabelTopConstraint = pageLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 8)

            // デフォルトはスライダー表示を前提に有効化（後で文脈に応じて切替）
            NSLayoutConstraint.activate(sliderConstraints)
            directLabelTopConstraint?.isActive = false
        }
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

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        
        // 読み方向選択
        let rightToLeftItem = NSMenuItem(title: "右綴じ", action: #selector(setRightToLeft(_:)), keyEquivalent: "")
        rightToLeftItem.target = self
        rightToLeftItem.state = isRightToLeftReading ? .on : .off
        menu.addItem(rightToLeftItem)
        
        let leftToRightItem = NSMenuItem(title: "左綴じ", action: #selector(setLeftToRight(_:)), keyEquivalent: "")
        leftToRightItem.target = self
        leftToRightItem.state = !isRightToLeftReading ? .on : .off
        menu.addItem(leftToRightItem)
        
        menu.addItem(NSMenuItem.separator())

        // 表示モード選択
        let autoModeItem = NSMenuItem(title: "自動", action: #selector(setViewModeAuto(_:)), keyEquivalent: "")
        autoModeItem.target = self
        autoModeItem.state = userPreferredViewMode == .auto ? .on : .off
        menu.addItem(autoModeItem)
        
        let singleModeItem = NSMenuItem(title: "単ページ", action: #selector(setViewModeSingle(_:)), keyEquivalent: "")
        singleModeItem.target = self
        singleModeItem.state = userPreferredViewMode == .single ? .on : .off
        menu.addItem(singleModeItem)
        
        let spreadModeItem = NSMenuItem(title: "見開き", action: #selector(setViewModeSpread(_:)), keyEquivalent: "")
        spreadModeItem.target = self
        spreadModeItem.state = userPreferredViewMode == .spread ? .on : .off
        menu.addItem(spreadModeItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 見開き補正メニュー
        let spreadOffsetItem = NSMenuItem(title: "見開きの左右を補正", action: #selector(toggleSpreadPairingOffset(_:)), keyEquivalent: "")
        spreadOffsetItem.target = self
        spreadOffsetItem.state = imageManager.getSpreadPairOffset() == 1 ? .on : .off
        menu.addItem(spreadOffsetItem)

        menu.addItem(NSMenuItem.separator())

        // ページ送りアニメ ON/OFF
        let transitionItem = NSMenuItem(title: "ページ送りアニメ", action: #selector(toggleTransition(_:)), keyEquivalent: "")
        transitionItem.target = self
        transitionItem.state = isTransitionEnabled ? .on : .off
        menu.addItem(transitionItem)
        
        // スライドショーメニュー
        let slideshowItem = NSMenuItem(title: "スライドショー", action: #selector(toggleSlideshow(_:)), keyEquivalent: "")
        slideshowItem.target = self
        slideshowItem.state = isSlideshowEnabled ? .on : .off
        menu.addItem(slideshowItem)

        // デコードキャッシュ方針（プレビュー表示のパフォーマンス最適化）
        let cacheMenuItem = NSMenuItem(title: "画像デコードキャッシュ", action: nil, keyEquivalent: "")
        let cacheMenu = NSMenu()
        let policy = AppSettings.shared.imageDecodeCachePolicy
        let noCache = NSMenuItem(title: "しない（最小メモリ）", action: #selector(setDecodeCacheNoCache(_:)), keyEquivalent: "")
        noCache.target = self
        noCache.state = policy == .noCache ? .on : .off
        cacheMenu.addItem(noCache)

        let deferred = NSMenuItem(title: "遅延（推奨）", action: #selector(setDecodeCacheDeferred(_:)), keyEquivalent: "")
        deferred.target = self
        deferred.state = policy == .deferred ? .on : .off
        cacheMenu.addItem(deferred)

        let immediate = NSMenuItem(title: "即時（最速/メモリ多め）", action: #selector(setDecodeCacheImmediate(_:)), keyEquivalent: "")
        immediate.target = self
        immediate.state = policy == .immediate ? .on : .off
        cacheMenu.addItem(immediate)

        cacheMenuItem.submenu = cacheMenu
        menu.addItem(NSMenuItem.separator())
        menu.addItem(cacheMenuItem)
        
        return menu
    }
    
    private func updateContextMenuStates() {
        // コンテキストメニューを再作成して状態を更新
        view.menu = makeContextMenu()
    }

    @objc private func toggleSpreadPairingOffset(_ sender: NSMenuItem) {
        imageManager.toggleSpreadPairOffset()
        // チェックマークを更新
        sender.state = imageManager.getSpreadPairOffset() == 1 ? .on : .off
        // 再描画（見開き時に効果、単ページでも次の見開きで反映）
        displayCurrentImage()
    }
    
    // 表示モード切替アクション
    @objc private func setViewModeAuto(_ sender: NSMenuItem) {
        userPreferredViewMode = .auto
        didRestoreViewModeFromHistory = true
        displayCurrentImage()
        updateContextMenuStates()
        // 履歴を保存（表示モード変更）
        saveReadingPositionToHistory()
    }
    
    @objc private func setViewModeSingle(_ sender: NSMenuItem) {
        userPreferredViewMode = .single
        didRestoreViewModeFromHistory = true
        displayCurrentImage()
        updateContextMenuStates()
        // 履歴を保存（表示モード変更）
        saveReadingPositionToHistory()
    }
    
    @objc private func setViewModeSpread(_ sender: NSMenuItem) {
        userPreferredViewMode = .spread
        didRestoreViewModeFromHistory = true
        displayCurrentImage()
        updateContextMenuStates()
        // 履歴を保存（表示モード変更）
        saveReadingPositionToHistory()
    }
    
    // 読み方向切替アクション
    @objc private func setRightToLeft(_ sender: NSMenuItem) {
        isRightToLeftReading = true
        didRestoreRTLFromHistory = true
        
        // UI要素を即座に更新
        applySliderLayoutDirection()
        syncSliderToCurrentPage()
        displayCurrentImage()
        updateContextMenuStates()
        // 履歴を保存
        saveReadingPositionToHistory()
    }
    
    @objc private func setLeftToRight(_ sender: NSMenuItem) {
        isRightToLeftReading = false
        didRestoreRTLFromHistory = true
        
        // UI要素を即座に更新
        applySliderLayoutDirection()
        syncSliderToCurrentPage()
        displayCurrentImage()
        updateContextMenuStates()
        // 履歴を保存
        saveReadingPositionToHistory()
    }
    
    @objc private func toggleReadingDirection(_ sender: NSMenuItem) {
        // 読み方向を切り替え
        isRightToLeftReading.toggle()
        didRestoreRTLFromHistory = true
        
        // チェックマークを更新（左綴じ時にチェック）
        sender.state = !isRightToLeftReading ? .on : .off
        
        // 設定を保存
        // セッション内のみ反映（永続化しない）
        
        // UI要素を即座に更新
        applySliderLayoutDirection()
        syncSliderToCurrentPage()
        displayCurrentImage()
        // 履歴を保存
        saveReadingPositionToHistory()
    }
    
    @objc private func toggleSlideshow(_ sender: NSMenuItem) {
        if isSlideshowEnabled {
            stopSlideshow()
        } else {
            startSlideshow()
        }
        // チェックマークを更新
        sender.state = isSlideshowEnabled ? .on : .off
    }

    // MARK: - Decode cache policy actions
    @objc private func setDecodeCacheNoCache(_ sender: NSMenuItem) {
        AppSettings.shared.imageDecodeCachePolicy = .noCache
        imageManager.clearCache()
        displayCurrentImage()
        updateContextMenuStates()
    }
    @objc private func setDecodeCacheDeferred(_ sender: NSMenuItem) {
        AppSettings.shared.imageDecodeCachePolicy = .deferred
        imageManager.clearCache()
        displayCurrentImage()
        updateContextMenuStates()
    }
    @objc private func setDecodeCacheImmediate(_ sender: NSMenuItem) {
        AppSettings.shared.imageDecodeCachePolicy = .immediate
        imageManager.clearCache()
        displayCurrentImage()
        updateContextMenuStates()
    }
    
    private func startSlideshow() {
        guard !isSlideshowEnabled else { return }
        isSlideshowEnabled = true
        
        let interval = loadSlideshowInterval()
        slideshowTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.advanceSlideshow()
        }
    }
    
    private func stopSlideshow() {
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
        let alwaysSingleForCover = loadAlwaysSinglePageForCover()
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
    
    // MARK: - Image Display
    
    private func displayCurrentImage() {
        // アスペクト比に基づいて表示モードを決定
        let useSpread = shouldUseSpreadMode()
        
        setViewMode(useSpread ? .spread : .single)
        
        if useSpread {
            // 見開き表示
            let (leftImage, rightImage) = imageManager.getSpreadImages(isRightToLeft: isRightToLeftReading)
            setImageSafely(leftImage, toImageView: imageView)
            setImageSafely(rightImage, toImageView: rightImageView)
        } else {
            // 単ページ表示
            if let currentImage = imageManager.getCurrentImage() {
                setImageSafely(currentImage, toImageView: imageView)
                currentImageAspect = (currentImage.size.height > 0) ? (currentImage.size.width / currentImage.size.height) : nil
            }
        }
        
        updatePageLabel()
        // スライダーの位置を現在ページに同期（方向反転に対応）
        syncSliderToCurrentPage()
        updatePreferredContentSizeIfNeeded()
    }
    
    private func updateImageDisplayOnly() {
        // 固定モード用：現在のViewModeを維持したまま画像表示のみ更新
        let currentMode = currentViewMode
        
        if currentMode == .spread {
            // 見開き表示
            let (leftImage, rightImage) = imageManager.getSpreadImages(isRightToLeft: isRightToLeftReading)
            setImageSafely(leftImage, toImageView: imageView)
            setImageSafely(rightImage, toImageView: rightImageView)
            
            // 見開き表示の場合は合成アスペクト比を計算
            calculateSpreadAspectRatio(leftImage: leftImage, rightImage: rightImage)
        } else {
            // 単ページ表示
            if let currentImage = imageManager.getCurrentImage() {
                setImageSafely(currentImage, toImageView: imageView)
                currentImageAspect = (currentImage.size.height > 0) ? (currentImage.size.width / currentImage.size.height) : nil
            }
        }
        
        updatePageLabel()
        syncSliderToCurrentPage()
        updatePreferredContentSizeIfNeeded()
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
        let noImageText = "ZIPファイル内に画像が見つかりませんでした"
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
    }

    // MARK: - Simple page push transition
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

    // トランジションのON/OFF切替
    @objc private func toggleTransition(_ sender: NSMenuItem) {
        isTransitionEnabled.toggle()
        sender.state = isTransitionEnabled ? .on : .off
    }

    // 保存フレーム読み出し/保存（共有UserDefaultsに統一）
    private func loadRestoreWindowFrameEnabled() -> Bool {
        return sharedDefaults().object(forKey: CZSettingsKeys.restoreWindowFrameEnabled) as? Bool ?? true
    }
    private func loadSavedWindowFrame() -> NSRect? {
        guard let s = sharedDefaults().string(forKey: CZSettingsKeys.savedWindowFrameString) else { return nil }
        return NSRectFromString(s)
    }
    private func saveWindowFrameIfEnabled() {
        guard (sharedDefaults().object(forKey: CZSettingsKeys.restoreWindowFrameEnabled) as? Bool ?? true), let win = view.window else { return }
        sharedDefaults().set(NSStringFromRect(win.frame), forKey: CZSettingsKeys.savedWindowFrameString)
    }

    private func setImageSafely(_ image: NSImage?, toImageView imageView: NSImageView?) {
        guard let iv = imageView else { return }
        // スケーリングのみ固定。アラインメントはモード切替で設定したものを維持する
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.image = image
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
        slider.isHidden = !visible
        slider.isEnabled = visible && imageManager.getImageCount() > 1
        // レイアウト方向も反映
        applySliderLayoutDirection()
        // 制約の切り替え
        if visible {
            if let c = directLabelTopConstraint { c.isActive = false }
            NSLayoutConstraint.activate(sliderConstraints)
        } else {
            NSLayoutConstraint.deactivate(sliderConstraints)
            if let c = directLabelTopConstraint { c.isActive = true }
        }
        view.layoutSubtreeIfNeeded()
    }

    // スライダーのハイライト向きを読書方向に合わせる
    private func applySliderLayoutDirection() {
        guard let slider = pageSlider else { return }
        if #available(macOS 10.12, *) {
            slider.userInterfaceLayoutDirection = isRightToLeftReading ? .rightToLeft : .leftToRight
        }
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
    }

    // 現在ページをスライダー位置へ反映（方向反転対応）
    private func syncSliderToCurrentPage() {
        guard let slider = pageSlider else { return }
        // 内部値はそのまま同期（見た目の方向はUIレベルで反映）
        let current = imageManager.getCurrentPageNumber()
        slider.integerValue = current
    }

    // Quick Look ホストに対して、縦方向いっぱいの希望サイズをヒントとして提示
    private func updatePreferredContentSizeIfNeeded() {
        // 1) 復元が有効で保存サイズがある場合は、それを優先して返す
        if loadRestoreWindowFrameEnabled(), let saved = loadSavedWindowFrame() {
            let sz = saved.size
            if preferredContentSize != sz { preferredContentSize = sz }
            return
        }
        // 2) 未保存/復元無効のときは、従来通り縦方向いっぱい
        guard let screen = view.window?.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame.size
        guard visible.height > 0 else { return }
        let aspect = currentImageAspect ?? (view.bounds.height > 0 ? max(view.bounds.width, 1) / view.bounds.height : 1.0)
        // まず高さを画面の可視領域いっぱいに
        var targetHeight = visible.height
        var targetWidth = aspect * targetHeight
        // 横幅が画面を超える場合は横に合わせて縮小
        if targetWidth > visible.width {
            targetWidth = visible.width
            targetHeight = max(1, targetWidth / max(aspect, 0.0001))
        }
        let size = NSSize(width: targetWidth, height: targetHeight)
        if preferredContentSize != size { preferredContentSize = size }
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

    // 指定ビュー座標が「通過させるべきNSControl」上かを判定（imageView配下は除外して吸収対象にする）
    private func isPointInsidePassThroughControl(_ pointInView: NSPoint) -> Bool {
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
    
    private func updatePageLabel() {
        let currentPage = imageManager.getCurrentPageNumber()
        let totalPages = imageManager.getImageCount()
        pageLabel?.stringValue = "\(currentPage) / \(totalPages)"
    }
    
    // キーボード入力はQuick Lookホストに委ねる（本拡張では未処理）
    
    // MARK: - Performance Optimization
    
    /// ImageManagerに現在のウィンドウサイズを設定して最適化を有効にする
    private func updateImageManagerDisplaySize() {
        guard let window = view.window else { return }
        
        let windowSize = window.frame.size
        let contentSize = view.bounds.size
        
        // 高DPIディスプレイ対応：実際の表示に必要なピクセル数を計算
        let backingScaleFactor = window.backingScaleFactor
        let targetSize = NSSize(
            width: max(contentSize.width, windowSize.width) * backingScaleFactor,
            height: max(contentSize.height, windowSize.height) * backingScaleFactor
        )
        
        // 最大サイズ制限（メモリ使用量を制御）
        let maxSize: CGFloat = 3840 // 4Kディスプレイ相当
        let limitedSize = NSSize(
            width: min(targetSize.width, maxSize),
            height: min(targetSize.height, maxSize)
        )
        
        imageManager.setTargetDisplaySize(limitedSize)
        
        NSLog("[Performance] Updated display size: %dx%d (scale: %f)", Int(limitedSize.width), Int(limitedSize.height), backingScaleFactor)
    }
    
    // MARK: - Reading History Management
    
    /// 履歴から前回の読書位置を復元
    private func restoreReadingPositionFromHistory() {
        guard !currentZipFilename.isEmpty else { return }
        
        if let history = readingHistoryManager.loadReadingPosition(filename: currentZipFilename) {
            NSLog("[ReadingHistory] Restoring position for %@: page %d, viewMode %@, offset %d, rtl %@", currentZipFilename, history.page, history.viewMode, history.spreadPairOffset, history.isRightToLeftReading?.description ?? "nil")
            
            // ページ位置を復元（全件読込中は保留し、完了後に適用）
            if imageManager.isLoadingAll {
                pendingRestorePage = history.page
            } else {
                _ = imageManager.goToPage(history.page)
            }
            
            // 見開きオフセットを復元
            imageManager.setSpreadPairOffset(history.spreadPairOffset)
            
            // 綴じ方向を復元（履歴にあれば）
            if let rtl = history.isRightToLeftReading {
                isRightToLeftReading = rtl
                didRestoreRTLFromHistory = true
                applySliderLayoutDirection()
                syncSliderToCurrentPage()
                updateContextMenuStates()
            }
            
            // 表示モードを履歴から復元（グローバルのデフォルトは変更しない）
            if let restored = PrefViewMode(rawValue: history.viewMode) {
                userPreferredViewMode = restored
                didRestoreViewModeFromHistory = true
                if imageManager.hasImages() { displayCurrentImage() }
                updateContextMenuStates()
            }
            // 表示モードはセッションごとにデフォルトへ初期化するため、履歴からは復元しない
            
            NSLog("[ReadingHistory] Position restored successfully")
        } else {
            NSLog("[ReadingHistory] No history found for %@", currentZipFilename)
        }
    }
    
    /// 現在の読書位置を履歴に保存
    private func saveReadingPositionToHistory() {
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
