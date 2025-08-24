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
            imageView?.image = currentImage
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
        
        imageView?.image = image
        pageLabel?.stringValue = ""
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
