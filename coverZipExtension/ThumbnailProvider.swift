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
     * アーカイブファイルから最初の画像を抽出してサムネイルを生成する
     * 
     * @param request サムネイル生成リクエスト（ファイルURLと最大サイズを含む）
     * @param handler 生成結果を返すコールバック関数
     */
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        
        // サムネイルサイズ（実ピクセル）
        let targetMaxPixels = max(1, Int(ceil(max(request.maximumSize.width, request.maximumSize.height) * request.scale)))

        // 1) ストリーミング展開 + 増分デコードで早期サムネイル生成を試みる
        let opts: CZFirstImageOptions = [.preferCoverLike, .preferZeroPaddedOne]
        let imageData: Data
        let archiveKind = CZArchiveKind.detect(at: request.fileURL)
        let result: CZFirstImageThumbnailResult = (archiveKind == .rar)
            ? CZRar.firstImageThumbnail(from: request.fileURL, options: opts, maxPixel: targetMaxPixels)
            : CZZip.firstImageThumbnail(from: request.fileURL, options: opts, maxPixel: targetMaxPixels)

        switch result {
        case .thumbnail(let cgImage):
            let cgSize = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
            let thumbSize = CZImageUtilities.calculateFitSize(for: cgSize, within: request.maximumSize)
            let reply = QLThumbnailReply(contextSize: thumbSize, currentContextDrawing: { () -> Bool in
                let imageRect = CZImageUtilities.calculateCenteredRect(for: cgSize, in: thumbSize)
                guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
                ctx.interpolationQuality = .high
                ctx.draw(cgImage, in: imageRect)
                return true
            })
            handler(reply, nil)
            return
        case .rawData(let data):
            // ストリーミング生成に失敗した画像データをそのまま再利用し、アーカイブの再読込・再選定を避ける
            imageData = data
        case .none:
            handler(nil, NSError(domain: "CoverZipError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No image found in archive file"]))
            return
        }

        // 2) フォールバック: 抽出済みデータからサムネイル生成
        let cfOptions = CZImageIOOptionsBuilder.buildThumbnailOptions(maxPixels: targetMaxPixels, cachePolicy: .noCache)
        guard let src = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgFallback = CGImageSourceCreateThumbnailAtIndex(src, 0, cfOptions) ?? CGImageSourceCreateImageAtIndex(src, 0, CZImageIOOptionsBuilder.buildDecodeOptions(cachePolicy: .noCache)) else {
            handler(nil, NSError(domain: "CoverZipError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage from data (fallback)"]))
            return
        }
        
        // デバッグ情報を出力
        NSLog("DEBUG: request.maximumSize = \(request.maximumSize)")
        NSLog("DEBUG: request.scale = \(request.scale)")
        NSLog("DEBUG: cgImage.size(px) = \(cgFallback.width)x\(cgFallback.height)")
        
        // 縦横比を維持したサムネイルを生成
        let cgImageSize = CGSize(width: CGFloat(cgFallback.width), height: CGFloat(cgFallback.height))
        let thumbnailSize = CZImageUtilities.calculateFitSize(for: cgImageSize, within: request.maximumSize)
        NSLog("DEBUG: calculated thumbnailSize = \(thumbnailSize)")

        let reply = QLThumbnailReply(contextSize: thumbnailSize, currentContextDrawing: { () -> Bool in
            // 画像を適切にスケーリングして中央に配置して描画（背景は透明）
            let imageRect = CZImageUtilities.calculateCenteredRect(for: cgImageSize, in: thumbnailSize)
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(cgFallback, in: imageRect)
            return true
        })
        
        handler(reply, nil)
    }
}

// サムネイル側のオプションヘルパは Shared/CZImageIOOptionsBuilder を使用
