//
//  PageProgressBarView.swift
//  coverZipViewer
//
//  Created by Nihondo on 2026/07/02.
//

import Cocoa

/// 画像の上に重ねて表示する、ページ位置を示す進捗塗りつぶし式のシークバー。
/// クリック・ドラッグでページをシークでき、塗りつぶし量が現在ページ/総ページ数を表す。
/// どんな画像背景の上でも輪郭が視認できるよう、トラック外周を黒線で縁取る。
final class PageProgressBarView: NSControl {

    /// シーク時に呼ばれる（1始まりのページ番号）
    var onSeek: ((Int) -> Void)?

    /// 読書方向（右綴じ時は塗りつぶし・シーク方向を反転）
    var isRightToLeftReading: Bool = false {
        didSet { needsDisplay = true }
    }

    private(set) var currentPage: Int = 1
    private(set) var totalPages: Int = 1

    private let trackInset: CGFloat = 1
    private let trackBackgroundColor = NSColor.white.withAlphaComponent(0.35)
    private let fillColor = NSColor.controlAccentColor.withAlphaComponent(0.6)
    private let borderColor = NSColor.black
    private let borderWidth: CGFloat = 1.25

    override var acceptsFirstResponder: Bool { false }

    /// 現在ページ・総ページ数を更新して再描画する
    func update(currentPage: Int, totalPages: Int) {
        self.currentPage = max(1, currentPage)
        self.totalPages = max(1, totalPages)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 0, bounds.height > 0 else { return }

        let trackRect = bounds.insetBy(dx: trackInset, dy: trackInset)
        // 端が半円になるピル形状（角丸半径 = 高さの半分）
        let cornerRadius = trackRect.height / 2
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: cornerRadius, yRadius: cornerRadius)

        // 背景トラック
        trackBackgroundColor.setFill()
        trackPath.fill()

        // 進捗塗りつぶし（RTL時は右起点）
        let ratio = fillRatio
        if ratio > 0 {
            NSGraphicsContext.saveGraphicsState()
            trackPath.addClip()
            var fillRect = trackRect
            fillRect.size.width = trackRect.width * ratio
            if isRightToLeftReading {
                fillRect.origin.x = trackRect.maxX - fillRect.width
            }
            fillColor.setFill()
            NSBezierPath(rect: fillRect).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        // 黒線の縁取り（様々な画像背景の上でも輪郭が沈まないよう最前面に描画）
        borderColor.setStroke()
        trackPath.lineWidth = borderWidth
        trackPath.stroke()

        drawPageText(in: trackRect)
    }

    private var fillRatio: CGFloat {
        guard totalPages > 1 else { return totalPages >= 1 ? 1 : 0 }
        return CGFloat(currentPage - 1) / CGFloat(totalPages - 1)
    }

    /// ページ番号テキストをバー中央に描画する（黒シャドウで背景に負けない視認性を確保）
    private func drawPageText(in rect: NSRect) {
        let text = "\(currentPage) / \(totalPages)"
        let font = NSFont.boldSystemFont(ofSize: 14)

        // 黒縁取り（ストロークのみ、太め）を先に描画し、後から白い塗り文字を重ねることで、
        // 縁取りが文字の外側だけに残るようにする（内側半分は白塗りに隠れる）
        let outlineAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .strokeColor: NSColor.black,
            .strokeWidth: 22.0
        ]
        let fillAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let outlineString = NSAttributedString(string: text, attributes: outlineAttributes)
        let fillString = NSAttributedString(string: text, attributes: fillAttributes)
        let textSize = fillString.size()
        let origin = NSPoint(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2
        )
        outlineString.draw(at: origin)
        fillString.draw(at: origin)
    }

    // MARK: - マウス操作（シーク）

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        seek(to: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        seek(to: event)
    }

    /// クリック/ドラッグ位置をページ番号へ変換してシークコールバックへ通知する
    private func seek(to event: NSEvent) {
        guard bounds.width > 0, totalPages > 0 else { return }
        let local = convert(event.locationInWindow, from: nil)
        var ratio = max(0, min(1, Double(local.x / bounds.width)))
        // RTL時は比率を反転（左端=最大ページ）
        if isRightToLeftReading { ratio = 1 - ratio }
        let page = 1 + Int((ratio * Double(totalPages - 1)).rounded())
        if page != currentPage {
            onSeek?(page)
        }
    }
}
