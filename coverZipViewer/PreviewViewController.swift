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

// MARK: - Preview View Controller

class PreviewViewController: NSViewController, QLPreviewingController {
    
    @IBOutlet weak var imageView: NSImageView!
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
    
    override var nibName: NSNib.Name? {
        return NSNib.Name("PreviewViewController")
    }

    override func loadView() {
        super.loadView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    // UserDefaultsから設定をロード
    isRightToLeftReading = AppSettings.shared.isRightToLeftReading
    sliderVisibilityWidthThreshold = CGFloat(AppSettings.shared.sliderVisibilityWidthThreshold)
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
                if self.isPointInsidePassThroughControl(vPoint) { return event }
                // マウスアップでページめくり処理を実行（画像エリアのみ）
                let bounds = self.view.bounds
                let isLeftHalf = vPoint.x < bounds.width / 2
                if self.isRightToLeftReading {
                    // 反転: 左=進む、右=戻る
                    if isLeftHalf {
                        if self.imageManager.nextImage() { self.displayCurrentImage() }
                    } else {
                        if self.imageManager.previousImage() { self.displayCurrentImage() }
                    }
                } else {
                    // 通常: 左=戻る、右=進む
                    if isLeftHalf {
                        if self.imageManager.previousImage() { self.displayCurrentImage() }
                    } else {
                        if self.imageManager.nextImage() { self.displayCurrentImage() }
                    }
                }
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
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
    // Quick LookではFirst Responderを取得しない
        // レイアウト完了後のサイズで初回画像を再フィット
        // 設定の変更を反映
        let newRTL = AppSettings.shared.isRightToLeftReading
        if newRTL != isRightToLeftReading { isRightToLeftReading = newRTL; applySliderLayoutDirection(); syncSliderToCurrentPage() }
        let newThreshold = CGFloat(AppSettings.shared.sliderVisibilityWidthThreshold)
        if newThreshold != sliderVisibilityWidthThreshold { sliderVisibilityWidthThreshold = newThreshold; updateSliderVisibilityForContext() }
        if imageManager.hasImages() {
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
    }
    

    /*
    func preparePreviewOfSearchableItem(identifier: String, queryString: String?) async throws {
        // Implement this method and set QLSupportsSearchableItems to YES in the Info.plist of the extension if you support CoreSpotlight.

        // Perform any setup necessary in order to prepare the view.
        // Quick Look will display a loading spinner until this returns.
    }
    */

    func preparePreviewOfFile(at url: URL) async throws {
        // ZIPファイルから画像を読み込む
        if imageManager.loadImages(from: url) {
            await MainActor.run {
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
        
        // Auto Layout制約の優先度調整
        setupConstraintPriorities()
        
        // キーイベントを受け取るためのResponder設定
        view.wantsLayer = true
        
        // 高品質な画像表示のための設定
        if let layer = imageView?.layer {
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
        
        // PageLabelの優先度を高く設定（サイズを保持）
        pageLabel.setContentHuggingPriority(.required, for: .horizontal)
        pageLabel.setContentHuggingPriority(.required, for: .vertical)
        pageLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        pageLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    }
    
    private func setupGestureRecognizers() {
        // フルスクリーンのため、クリックはローカルモニタで処理する
    }
    
    @objc private func handleClick(_ gesture: NSClickGestureRecognizer) {}

    // ダブルクリック時は何もしない（シングルクリックハンドラで検知して無視）
    
    // MARK: - Image Display
    
    private func displayCurrentImage() {
        if let currentImage = imageManager.getCurrentImage() {
            setImageSafely(currentImage)
            updatePageLabel()
            // スライダーの位置を現在ページに同期（方向反転に対応）
            syncSliderToCurrentPage()
            // 画像のアスペクト比に基づいて縦いっぱいの希望サイズを提示
            currentImageAspect = (currentImage.size.height > 0) ? (currentImage.size.width / currentImage.size.height) : nil
            updatePreferredContentSizeIfNeeded()
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

    private func setImageSafely(_ image: NSImage) {
        guard let iv = imageView else { return }
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.imageAlignment = .alignCenter
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
        // スライダーの見た目方向はRTLに合わせているため、内部値は反転しない
        let page = sender.integerValue
        if imageManager.goToPage(Int(page)) {
            displayCurrentImage()
        }
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
            if let iv = self.imageView, cur === iv { return false }
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
