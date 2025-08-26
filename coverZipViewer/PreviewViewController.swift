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
    // ページ切替トランジション（既定ON）
    private var isTransitionEnabled: Bool = true
    
    // 表示モード
    enum ViewMode {
        case single
        case spread
    }
    private var currentViewMode: ViewMode = .single
    private var didApplyInitialViewMode = false

    // App Group UserDefaults ヘルパー（AppSettings 非依存化）
    private let appGroupID = "group.com.dmng.CoverZip"
    private func sharedDefaults() -> UserDefaults { UserDefaults(suiteName: appGroupID) ?? .standard }
    private func loadIsRTL() -> Bool { sharedDefaults().object(forKey: "isRightToLeftReading") as? Bool ?? true }
    private func loadSliderThreshold() -> CGFloat { CGFloat(sharedDefaults().object(forKey: "sliderVisibilityWidthThreshold") as? Double ?? 600.0) }
    private func loadAlwaysSinglePageForCover() -> Bool { sharedDefaults().object(forKey: "alwaysSinglePageForCover") as? Bool ?? true }
    private enum PrefViewMode: String { case auto, single, spread }
    private func loadDefaultViewMode() -> PrefViewMode { PrefViewMode(rawValue: sharedDefaults().string(forKey: "defaultViewMode") ?? "auto") ?? .auto }
    private func loadSlideshowEnabled() -> Bool { sharedDefaults().object(forKey: "slideshowEnabled") as? Bool ?? false }
    private func loadSlideshowInterval() -> Double { sharedDefaults().object(forKey: "slideshowInterval") as? Double ?? 3.0 }
    
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
        setupUI()
        setupGestureRecognizers()
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
                // スライダーなどのNSControl（やそのサブビュー）上のクリックは通す（ただしimageView配下は除外）
                if self.isPointInsidePassThroughControl(p) {
                    // A案: スライダートラック上クリック時は即時に値を反映してアクション実行（イベントは通す）
                    self.immediatelyJumpSliderIfNeeded(atViewPoint: p)
                    print("[DEBUG] Mouse down passed through to control")
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
        if let up = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] event -> NSEvent? in
            guard let self else { return event }
            if self.view.window != nil {
                // 座標変換に失敗したら安全側でイベントを通す
                guard let vPoint = self.convertEventPointToView(event) else { return event }
                // 自ビュー領域外はホストに渡す
                guard self.view.bounds.contains(vPoint) else { return event }
                // スライダーなどのNSControl（やそのサブビュー）上のクリックは通す（ただしimageView配下は除外）
                if self.isPointInsidePassThroughControl(vPoint) { 
                    print("[DEBUG] Click passed through to control")
                    return event 
                }
                // マウスアップでページめくり処理を実行（画像エリアのみ）
                let bounds = self.view.bounds
                let isLeftHalf = vPoint.x < bounds.width / 2
                let isSpreadMode = self.currentViewMode == .spread
                
                print("[DEBUG] Click detected at (\(vPoint.x), \(vPoint.y)) in bounds \(bounds), isLeftHalf=\(isLeftHalf), isSpreadMode=\(isSpreadMode)")
                
                // スライドショー中の手動操作は一時的に停止・再開
                let wasSlideshow = self.isSlideshowEnabled
                if wasSlideshow { self.stopSlideshow() }
                
                if self.isRightToLeftReading {
                    // 反転: 左=進む、右=戻る
                    if isLeftHalf {
                        print("[DEBUG] RTL: Left click - Next page")
                        if self.imageManager.nextImage(isSpreadMode: isSpreadMode) {
                            // ViewModeを決定してからアニメ適用
                            self.setViewMode(self.shouldUseSpreadMode() ? .spread : .single)
                            self.applyTransition(forward: true)
                            self.displayCurrentImage()
                        }
                    } else {
                        print("[DEBUG] RTL: Right click - Previous page")
                        if self.imageManager.previousImage(isSpreadMode: isSpreadMode) {
                            self.setViewMode(self.shouldUseSpreadMode() ? .spread : .single)
                            self.applyTransition(forward: false)
                            self.displayCurrentImage()
                        }
                    }
                } else {
                    // 通常: 左=戻る、右=進む
                    if isLeftHalf {
                        print("[DEBUG] LTR: Left click - Previous page")
                        if self.imageManager.previousImage(isSpreadMode: isSpreadMode) {
                            self.setViewMode(self.shouldUseSpreadMode() ? .spread : .single)
                            self.applyTransition(forward: false)
                            self.displayCurrentImage()
                        }
                    } else {
                        print("[DEBUG] LTR: Right click - Next page")
                        if self.imageManager.nextImage(isSpreadMode: isSpreadMode) {
                            self.setViewMode(self.shouldUseSpreadMode() ? .spread : .single)
                            self.applyTransition(forward: true)
                            self.displayCurrentImage()
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
        for m in mouseMonitors { NSEvent.removeMonitor(m) }
        mouseMonitors.removeAll()
        pendingSingleClick?.cancel()
        pendingSingleClick = nil
        // スライドショーのクリーンアップ
        stopSlideshow()
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
    // Quick LookではFirst Responderを取得しない
        // レイアウト完了後のサイズで初回画像を再フィット
        // 設定の変更を反映
    let newRTL = loadIsRTL()
        if newRTL != isRightToLeftReading { isRightToLeftReading = newRTL; applySliderLayoutDirection(); syncSliderToCurrentPage() }
    let newThreshold = loadSliderThreshold()
        if newThreshold != sliderVisibilityWidthThreshold { sliderVisibilityWidthThreshold = newThreshold; updateSliderVisibilityForContext() }
        if imageManager.hasImages() {
            applyInitialViewModeIfNeeded()
            displayCurrentImage()
        }
        // ホストにサイズ希望を伝える（可能なら）
        updatePreferredContentSizeIfNeeded()
    // 表示コンテキストに応じてスライダー可視性を更新
    updateSliderVisibilityForContext()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // 自動リサイズ機能を使用するため、手動でのリサイズ処理は不要
        // レイアウト変化に応じてスライダーの可視性を見直す
        updateSliderVisibilityForContext()
        // アスペクト比変更に応じて表示モードを再評価
        if imageManager.hasImages() {
            // レイアウト変更時は基本オート。ただし初回のユーザ設定は維持済み
            displayCurrentImage()
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
        
        // 読み方向をデフォルトの右綴じ（RTL）にリセット
        isRightToLeftReading = true
        
        // ZIPファイルから画像を読み込む
        if imageManager.loadImages(from: url) {
            await MainActor.run {
                // 初回表示モードをユーザー設定に基づき適用
                applyInitialViewModeIfNeeded()
                // UI要素を更新（読み方向変更を反映）
                applySliderLayoutDirection()
                syncSliderToCurrentPage()
                displayCurrentImage()
                // 初期ロード時に隣接画像を先読み
                imageManager.preloadAdjacentImages()
                updateSliderLimits()
            }
        } else {
            // 画像が見つからない場合の処理
            await MainActor.run {
                displayNoImagesMessage()
            }
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
        
        // 左綴じメニュー（左綴じ時にチェック）
        let leftToRightItem = NSMenuItem(title: "左綴じ", action: #selector(toggleReadingDirection(_:)), keyEquivalent: "")
        leftToRightItem.target = self
        leftToRightItem.state = !isRightToLeftReading ? .on : .off
        menu.addItem(leftToRightItem)
        
    // 見開き補正メニュー
    let spreadOffsetItem = NSMenuItem(title: "見開きの左右を1ページ補正", action: #selector(toggleSpreadPairingOffset(_:)), keyEquivalent: "")
    spreadOffsetItem.target = self
    spreadOffsetItem.state = imageManager.getSpreadPairOffset() == 1 ? .on : .off
    menu.addItem(spreadOffsetItem)

    // セパレータ（この直下にアニメーショントグルを配置）
    menu.addItem(NSMenuItem.separator())

    // ページ送りアニメ ON/OFF（直下）
    let transitionItem = NSMenuItem(title: "ページ送りアニメ", action: #selector(toggleTransition(_:)), keyEquivalent: "")
    transitionItem.target = self
    transitionItem.state = isTransitionEnabled ? .on : .off
    menu.addItem(transitionItem)
        
        // スライドショーメニュー
        let slideshowItem = NSMenuItem(title: "スライドショー", action: #selector(toggleSlideshow(_:)), keyEquivalent: "")
        slideshowItem.target = self
        slideshowItem.state = isSlideshowEnabled ? .on : .off
        menu.addItem(slideshowItem)
        
        return menu
    }

    @objc private func toggleSpreadPairingOffset(_ sender: NSMenuItem) {
        imageManager.toggleSpreadPairOffset()
        // チェックマークを更新
        sender.state = imageManager.getSpreadPairOffset() == 1 ? .on : .off
        // 再描画（見開き時に効果、単ページでも次の見開きで反映）
        displayCurrentImage()
    }
    
    @objc private func toggleReadingDirection(_ sender: NSMenuItem) {
        // 読み方向を切り替え
        isRightToLeftReading.toggle()
        
        // チェックマークを更新（左綴じ時にチェック）
        sender.state = !isRightToLeftReading ? .on : .off
        
        // 設定を保存
        sharedDefaults().set(isRightToLeftReading, forKey: "isRightToLeftReading")
        
        // UI要素を即座に更新
        applySliderLayoutDirection()
        syncSliderToCurrentPage()
        displayCurrentImage()
    }
    
    @objc private func toggleSlideshow(_ sender: NSMenuItem) {
        if isSlideshowEnabled {
            stopSlideshow()
        } else {
            startSlideshow()
        }
        // チェックマークを更新
        sender.state = isSlideshowEnabled ? .on : .off
        // 設定を保存
        sharedDefaults().set(isSlideshowEnabled, forKey: "slideshowEnabled")
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
        
        if isRightToLeftReading {
            // RTL: 次のページへ進む
            if !imageManager.nextImage(isSpreadMode: isSpreadMode) {
                // 最後のページに到達したらスライドショーを停止
                stopSlideshow()
                // メニューの更新（実際の更新は次回メニュー表示時）
                return
            }
        } else {
            // LTR: 次のページへ進む
            if !imageManager.nextImage(isSpreadMode: isSpreadMode) {
                // 最後のページに到達したらスライドショーを停止
                stopSlideshow()
                return
            }
        }
        
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
        // デフォルト表示モードの設定を優先（初回適用時に currentViewMode を設定）
        // ここは通常の自動判定。
        let bounds = view.bounds
        let isLandscape = bounds.width > bounds.height
    let alwaysSingleForCover = loadAlwaysSinglePageForCover()
        let isCover = imageManager.isCoverPage()
        
        return isLandscape && (!alwaysSingleForCover || !isCover)
    }

    private func applyInitialViewModeIfNeeded() {
        guard !didApplyInitialViewMode else { return }
        didApplyInitialViewMode = true
        let pref = loadDefaultViewMode()
        switch pref {
        case .auto:
            // 何もしない（後続の shouldUseSpreadMode に委ねる）
            break
        case .single:
            setViewMode(.single)
        case .spread:
            if loadAlwaysSinglePageForCover() && imageManager.isCoverPage() {
                setViewMode(.single)
            } else {
                setViewMode(.spread)
            }
        }
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
        // Finderカラム内は狭い幅で表示されることが多い。閾値未満は非表示。
        return view.bounds.width < sliderVisibilityWidthThreshold
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

}
