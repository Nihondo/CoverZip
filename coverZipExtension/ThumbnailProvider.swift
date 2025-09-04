//
//  ThumbnailProvider.swift
//  coverZipExtension
//
//  Created by Nihondo on 2025/07/15.
//

import QuickLookThumbnailing
import Foundation
import AppKit
import ImageIO

class ThumbnailProvider: QLThumbnailProvider {
    
    /**
     * QuickLook拡張機能のメインエントリーポイント
     * ZIPファイルから最初の画像を抽出してサムネイルを生成する
     * 
     * @param request サムネイル生成リクエスト（ファイルURLと最大サイズを含む）
     * @param handler 生成結果を返すコールバック関数
     */
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        
        // ZIPファイルから最初の画像を抽出してサムネイルを生成
        // 先頭判定の早期化（01/001/... や image001 などの0埋め1を優先）を有効化
        guard let imageData = ZipProcessor.extractFirstImageFromZip(at: request.fileURL, isZeroPaddedFirstPreferred: true) else {
            handler(nil, NSError(domain: "CoverZipError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No image found in ZIP file"]))
            return
        }
        
        // CGImageSource を用いたサムネイル生成（フルデコードを回避し高速化）
        let targetMaxPixels = max(1, Int(ceil(max(request.maximumSize.width, request.maximumSize.height) * request.scale)))
        let cfOptions = CZImageIOOptionsBuilder.buildThumbnailOptions(maxPixels: targetMaxPixels, cachePolicy: .noCache)

        guard let src = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(src, 0, cfOptions) ?? CGImageSourceCreateImageAtIndex(src, 0, CZImageIOOptionsBuilder.buildDecodeOptions(cachePolicy: .noCache)) else {
            handler(nil, NSError(domain: "CoverZipError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage from data"]))
            return
        }
        
        // デバッグ情報を出力
        NSLog("DEBUG: request.maximumSize = \(request.maximumSize)")
        NSLog("DEBUG: request.scale = \(request.scale)")
        NSLog("DEBUG: cgImage.size(px) = \(cgImage.width)x\(cgImage.height)")
        
        // 縦横比を維持したサムネイルを生成
        let cgImageSize = NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        let thumbnailSize = calculateThumbnailSize(for: cgImageSize, maxSize: request.maximumSize)
        NSLog("DEBUG: calculated thumbnailSize = \(thumbnailSize)")
        
        let reply = QLThumbnailReply(contextSize: thumbnailSize, currentContextDrawing: { () -> Bool in
            // 背景を白で塗りつぶす
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: thumbnailSize)).fill()
            
            // 画像を適切にスケーリングして中央に配置して描画
            let imageRect = self.calculateScaledImageRect(imageSize: cgImageSize, canvasSize: thumbnailSize)
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(cgImage, in: imageRect)
            
            return true
        })
        
        handler(reply, nil)
    }
    
    
    /**
     * 画像の縦横比を維持したサムネイルサイズを計算する
     * 最大サイズの制限内で、元画像の縦横比を保持し、クロップされないよう適切にスケーリングする
     * 
     * @param imageSize 元画像のサイズ
     * @param maxSize 最大許容サイズ
     * @return 計算されたサムネイルサイズ
     */
    private func calculateThumbnailSize(for imageSize: NSSize, maxSize: CGSize) -> CGSize {
        let imageAspectRatio = imageSize.width / imageSize.height
        let maxAspectRatio = maxSize.width / maxSize.height
        
        var thumbnailWidth: CGFloat
        var thumbnailHeight: CGFloat
        
        if imageAspectRatio > maxAspectRatio {
            // 画像が最大サイズより横長の場合、幅を基準にスケーリング
            thumbnailWidth = maxSize.width
            thumbnailHeight = thumbnailWidth / imageAspectRatio
        } else {
            // 画像が最大サイズより縦長または同じ縦横比の場合、高さを基準にスケーリング
            thumbnailHeight = maxSize.height
            thumbnailWidth = thumbnailHeight * imageAspectRatio
        }
        
        return CGSize(width: thumbnailWidth, height: thumbnailHeight)
    }
    
    /**
     * 画像を適切にスケーリングしてキャンバスの中央に配置するための矩形を計算する
     * 画像の縦横比を維持しながら、キャンバスサイズ内に収まるように縮小する
     * 
     * @param imageSize 元画像のサイズ
     * @param canvasSize キャンバスのサイズ
     * @return スケーリングされ中央配置された画像の矩形
     */
    private func calculateScaledImageRect(imageSize: NSSize, canvasSize: CGSize) -> NSRect {
        // 画像の縦横比を計算
        let imageAspectRatio = imageSize.width / imageSize.height
        let canvasAspectRatio = canvasSize.width / canvasSize.height
        
        var scaledWidth: CGFloat
        var scaledHeight: CGFloat
        
        if imageAspectRatio > canvasAspectRatio {
            // 画像が横長の場合、幅を基準にスケーリング
            scaledWidth = canvasSize.width
            scaledHeight = scaledWidth / imageAspectRatio
        } else {
            // 画像が縦長または正方形の場合、高さを基準にスケーリング
            scaledHeight = canvasSize.height
            scaledWidth = scaledHeight * imageAspectRatio
        }
        
        // 中央配置のための座標を計算
        let x = (canvasSize.width - scaledWidth) / 2
        let y = (canvasSize.height - scaledHeight) / 2
        
        return NSRect(x: x, y: y, width: scaledWidth, height: scaledHeight)
    }
}

// サムネイル側のオプションヘルパは Shared/CZImageIOOptionsBuilder を使用
