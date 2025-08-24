//
//  PreviewViewController.swift
//  coverZipViewer
//
//  Created by Nihondo on 2025/08/24.
//

import Cocoa
import Quartz

class PreviewViewController: NSViewController, QLPreviewingController {
    
    @IBOutlet weak var imageView: NSImageView!
    @IBOutlet weak var pageLabel: NSTextField!
    
    private var imageManager = ImageManager()
    private var mouseMonitors: [Any] = []
    private var lastCanvasSize: CGSize?
    
    override var nibName: NSNib.Name? {
        return NSNib.Name("PreviewViewController")
    }

    override func loadView() {
        super.loadView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupGestureRecognizers()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // ダブルクリックをホスト（Finder）へ渡さないためにローカルモニタで吸収（down/up 両方）
    if let down = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] event in
            guard let self else { return event }
            if self.view.window != nil, event.clickCount >= 2 { return nil }
            return event
    }) {
            mouseMonitors.append(down)
        }
    if let up = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] event in
            guard let self else { return event }
            if self.view.window != nil, event.clickCount >= 2 { return nil }
            return event
    }) {
            mouseMonitors.append(up)
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        for m in mouseMonitors { NSEvent.removeMonitor(m) }
        mouseMonitors.removeAll()
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        // ビューが表示されたらFirst Responderになってキーイベントを受け取る
        view.window?.makeFirstResponder(self)
        // レイアウト完了後のサイズで初回画像を再フィット
        if imageManager.hasImages() {
            displayCurrentImage()
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // キャンバスサイズが変わったら再レンダリング
        let canvas = currentCanvasSize()
        if let last = lastCanvasSize {
            if abs(last.width - canvas.width) > 0.5 || abs(last.height - canvas.height) > 0.5 {
                if imageManager.hasImages() { displayCurrentImage() }
            }
        } else {
            if imageManager.hasImages() { displayCurrentImage() }
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
        // ZIPファイルから画像を読み込む
        if imageManager.loadImages(from: url) {
            await MainActor.run {
                displayCurrentImage()
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
        imageView?.imageScaling = .scaleProportionallyUpOrDown
        imageView?.imageAlignment = .alignCenter
        
        // キーイベントを受け取るためのResponder設定
        view.wantsLayer = true
    // レイヤーは使わず、都度アスペクトフィットでラスタライズして表示
    }
    
    private func setupGestureRecognizers() {
    // シングルクリックでページ送り（ダブルクリックはローカルモニタで吸収）
    let singleClick = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
    singleClick.numberOfClicksRequired = 1
    view.addGestureRecognizer(singleClick)
    }
    
    @objc private func handleClick(_ gesture: NSClickGestureRecognizer) {
        let location = gesture.location(in: view)
        let viewWidth = view.bounds.width
        
        if location.x < viewWidth / 2 {
            // 左半分がクリックされた場合 - 前の画像
            if imageManager.previousImage() {
                displayCurrentImage()
            }
        } else {
            // 右半分がクリックされた場合 - 次の画像
            if imageManager.nextImage() {
                displayCurrentImage()
            }
        }
    }

    // ダブルクリック時は何もしない（シングルクリックハンドラで検知して無視）
    
    // MARK: - Image Display
    
    private func displayCurrentImage() {
        if let currentImage = imageManager.getCurrentImage() {
            setImageSafely(currentImage)
            updatePageLabel()
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
        
        imageView?.imageScaling = .scaleNone
        imageView?.imageAlignment = .alignCenter
        imageView?.image = renderAspectFit(image, canvasSize: imageView?.bounds.size ?? view.bounds.size)
        pageLabel?.stringValue = ""
    }

    // キャンバスサイズにアスペクトフィットで描画したビットマップを返す
    private func setImageSafely(_ image: NSImage) {
        guard let iv = imageView else { return }
    let canvas = currentCanvasSize()
        iv.imageScaling = .scaleNone
        iv.imageAlignment = .alignCenter
        iv.image = renderAspectFit(image, canvasSize: canvas)
    lastCanvasSize = canvas
        iv.needsDisplay = true
    }

    private func renderAspectFit(_ image: NSImage, canvasSize: CGSize) -> NSImage {
        let canvasSize = CGSize(width: max(1, canvasSize.width), height: max(1, canvasSize.height))
        let result = NSImage(size: canvasSize)
        result.lockFocus()
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()
        let imgSize = image.size
        guard imgSize.width > 0 && imgSize.height > 0 else {
            result.unlockFocus(); return result
        }
        let scale = min(canvasSize.width / imgSize.width, canvasSize.height / imgSize.height)
        let drawSize = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
        let origin = CGPoint(x: (canvasSize.width - drawSize.width) / 2, y: (canvasSize.height - drawSize.height) / 2)
        image.draw(in: NSRect(origin: origin, size: drawSize), from: NSRect(origin: .zero, size: imgSize), operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
        result.unlockFocus()
        return result
    }

    private func currentCanvasSize() -> CGSize {
        if let iv = imageView {
            let s = iv.bounds.size
            if s.width > 0 && s.height > 0 { return s }
        }
        let vs = view.bounds.size
        return CGSize(width: max(1, vs.width), height: max(1, vs.height))
    }
    
    private func updatePageLabel() {
        let currentPage = imageManager.getCurrentPageNumber()
        let totalPages = imageManager.getImageCount()
        pageLabel?.stringValue = "\(currentPage) / \(totalPages)"
    }
    
    // MARK: - Keyboard Events
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: // 上矢印キー - 前の画像
            if imageManager.previousImage() {
                displayCurrentImage()
            }
        case 125: // 下矢印キー - 次の画像
            if imageManager.nextImage() {
                displayCurrentImage()
            }
        case 49: // スペースキー
            if event.modifierFlags.contains(.shift) {
                // Shift+スペース - 前の画像
                if imageManager.previousImage() {
                    displayCurrentImage()
                }
            } else {
                // スペースキー - 次の画像
                if imageManager.nextImage() {
                    displayCurrentImage()
                }
            }
        default:
            super.keyDown(with: event)
        }
    }

}
