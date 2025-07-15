//
//  ThumbnailProvider.swift
//  coverZipExtension
//
//  Created by Nihondo on 2025/07/15.
//

import QuickLookThumbnailing
import Foundation
import AppKit
import Compression

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
        guard let imageData = extractFirstImageFromZip(at: request.fileURL) else {
            handler(nil, NSError(domain: "CoverZipError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No image found in ZIP file"]))
            return
        }
        
        guard let image = NSImage(data: imageData) else {
            handler(nil, NSError(domain: "CoverZipError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create image from data"]))
            return
        }
        
        // デバッグ情報を出力
        NSLog("DEBUG: request.maximumSize = \(request.maximumSize)")
        NSLog("DEBUG: request.scale = \(request.scale)")
        NSLog("DEBUG: image.size = \(image.size)")
        
        // 縦横比を維持したサムネイルを生成
        let thumbnailSize = calculateThumbnailSize(for: image.size, maxSize: request.maximumSize)
        NSLog("DEBUG: calculated thumbnailSize = \(thumbnailSize)")
        
        let reply = QLThumbnailReply(contextSize: thumbnailSize, currentContextDrawing: { () -> Bool in
            // 背景を白で塗りつぶす
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: thumbnailSize)).fill()
            
            // 画像を適切にスケーリングして中央に配置して描画
            let imageRect = self.calculateScaledImageRect(imageSize: image.size, canvasSize: thumbnailSize)
            image.draw(in: imageRect)
            
            return true
        })
        
        handler(reply, nil)
    }
    
    /**
     * ZIPファイルから最初の画像ファイルを抽出する
     * 
     * @param url ZIPファイルのURL
     * @return 画像データ（見つからない場合はnil）
     */
    private func extractFirstImageFromZip(at url: URL) -> Data? {
        do {
            let data = try Data(contentsOf: url)
            return parseZipAndFindFirstImage(data: data)
        } catch {
            NSLog("Error reading ZIP file: \(error)")
            return nil
        }
    }
    
    /**
     * ZIPファイルデータを解析し、最初の画像ファイルを検索する
     * 
     * @param data ZIPファイルのバイナリデータ
     * @return 最初に見つかった画像ファイルのデータ（見つからない場合はnil）
     */
    private func parseZipAndFindFirstImage(data: Data) -> Data? {
        // ZIP Central Directory の検索
        guard let centralDirectoryOffset = findCentralDirectoryOffset(in: data) else {
            return nil
        }
        
        // Central Directory からファイルエントリを読み取り
        let entries = parseCentralDirectory(data: data, offset: centralDirectoryOffset)
        
        // 最初の画像ファイルを探す
        for entry in entries {
            if isImageFile(filename: entry.filename) {
                return extractFileData(data: data, entry: entry)
            }
        }
        
        return nil
    }
    
    /**
     * ZIPファイル内のCentral Directoryの位置を検索する
     * End of Central Directory Record（EOCDR）から逆算して位置を特定
     * 
     * @param data ZIPファイルのバイナリデータ
     * @return Central Directoryの開始オフセット（見つからない場合はnil）
     */
    private func findCentralDirectoryOffset(in data: Data) -> Int? {
        // End of Central Directory Record の検索 (0x06054b50)
        let eocdrSignature: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        
        // ファイルの最後から検索
        let searchRange = max(0, data.count - 65536)
        for i in stride(from: data.count - 4, through: searchRange, by: -1) {
            if data.subdata(in: i..<i+4).elementsEqual(eocdrSignature) {
                // Central Directory のオフセットを取得 (16バイト後)
                let offsetBytes = data.subdata(in: i+16..<i+20)
                let offset = offsetBytes.withUnsafeBytes { $0.load(as: UInt32.self) }
                return Int(offset)
            }
        }
        
        return nil
    }
    
    /**
     * Central Directoryを解析してファイルエントリのリストを作成する
     * 
     * @param data ZIPファイルのバイナリデータ
     * @param offset Central Directoryの開始オフセット
     * @return ZIPファイル内のファイルエントリのリスト
     */
    private func parseCentralDirectory(data: Data, offset: Int) -> [ZipEntry] {
        var entries: [ZipEntry] = []
        var currentOffset = offset
        
        while currentOffset < data.count - 4 {
            // Central Directory File Header の署名をチェック (0x02014b50)
            let signature = data.subdata(in: currentOffset..<currentOffset+4)
            let expectedSignature: [UInt8] = [0x50, 0x4b, 0x01, 0x02]
            
            if !signature.elementsEqual(expectedSignature) {
                break
            }
            
            // ファイル名の長さを取得
            let filenameLength = data.subdata(in: currentOffset+28..<currentOffset+30).withUnsafeBytes { $0.load(as: UInt16.self) }
            let extraFieldLength = data.subdata(in: currentOffset+30..<currentOffset+32).withUnsafeBytes { $0.load(as: UInt16.self) }
            let commentLength = data.subdata(in: currentOffset+32..<currentOffset+34).withUnsafeBytes { $0.load(as: UInt16.self) }
            
            // ファイル名を取得
            let filenameData = data.subdata(in: currentOffset+46..<currentOffset+46+Int(filenameLength))
            let filename = String(data: filenameData, encoding: .utf8) ?? ""
            
            // Local File Header のオフセットを取得
            let localHeaderOffset = data.subdata(in: currentOffset+42..<currentOffset+46).withUnsafeBytes { $0.load(as: UInt32.self) }
            
            entries.append(ZipEntry(filename: filename, localHeaderOffset: Int(localHeaderOffset)))
            
            // 次のエントリに移動
            currentOffset += 46 + Int(filenameLength) + Int(extraFieldLength) + Int(commentLength)
        }
        
        return entries
    }
    
    /**
     * ファイル名が画像ファイルかどうかを判定する
     * 対応形式: .jpg, .jpeg, .png, .gif, .bmp, .tiff, .tif, .ico, .icns
     * 除外: __MACOSX フォルダ内のファイル、隠しファイル（.で始まる）
     * 
     * @param filename 判定対象のファイル名
     * @return 画像ファイルの場合はtrue、そうでなければfalse
     */
    private func isImageFile(filename: String) -> Bool {
        let lowercaseFilename = filename.lowercased()
        let imageExtensions = [".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".tif", ".ico", ".icns"]
        
        // __MACOSX フォルダは無視
        if lowercaseFilename.contains("__macosx") {
            return false
        }
        
        // 隠しファイルは無視
        if filename.hasPrefix(".") {
            return false
        }
        
        return imageExtensions.contains { lowercaseFilename.hasSuffix($0) }
    }
    
    /**
     * ZIPファイル内の指定されたファイルエントリからデータを抽出する
     * Local File Headerを解析し、圧縮方法に応じて展開処理を行う
     * 
     * @param data ZIPファイルのバイナリデータ
     * @param entry 抽出対象のファイルエントリ
     * @return 展開されたファイルデータ（失敗した場合はnil）
     */
    private func extractFileData(data: Data, entry: ZipEntry) -> Data? {
        let offset = entry.localHeaderOffset
        
        // Local File Header の署名をチェック (0x04034b50)
        let signature = data.subdata(in: offset..<offset+4)
        let expectedSignature: [UInt8] = [0x50, 0x4b, 0x03, 0x04]
        
        if !signature.elementsEqual(expectedSignature) {
            return nil
        }
        
        // ファイル名の長さと Extra Field の長さを取得
        let filenameLength = data.subdata(in: offset+26..<offset+28).withUnsafeBytes { $0.load(as: UInt16.self) }
        let extraFieldLength = data.subdata(in: offset+28..<offset+30).withUnsafeBytes { $0.load(as: UInt16.self) }
        
        // 圧縮されたファイルサイズを取得
        let compressedSize = data.subdata(in: offset+18..<offset+22).withUnsafeBytes { $0.load(as: UInt32.self) }
        
        // 圧縮方法を取得
        let compressionMethod = data.subdata(in: offset+8..<offset+10).withUnsafeBytes { $0.load(as: UInt16.self) }
        
        // ファイルデータの開始位置
        let fileDataOffset = offset + 30 + Int(filenameLength) + Int(extraFieldLength)
        let fileData = data.subdata(in: fileDataOffset..<fileDataOffset+Int(compressedSize))
        
        // 圧縮方法に応じて展開
        if compressionMethod == 0 {
            // 非圧縮
            return fileData
        } else if compressionMethod == 8 {
            // DEFLATE 圧縮
            return inflateData(fileData)
        }
        
        return nil
    }
    
    /**
     * DEFLATE圧縮されたデータを展開する
     * Apple標準のCompressionフレームワークを使用
     * 
     * @param compressedData 圧縮されたデータ
     * @return 展開されたデータ（失敗した場合はnil）
     */
    private func inflateData(_ compressedData: Data) -> Data? {
        return compressedData.withUnsafeBytes { bytes in
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024 * 1024) // 1MB buffer
            defer { buffer.deallocate() }
            
            let decompressedSize = compression_decode_buffer(buffer, 1024 * 1024, bytes.bindMemory(to: UInt8.self).baseAddress!, compressedData.count, nil, COMPRESSION_ZLIB)
            
            if decompressedSize > 0 {
                return Data(bytes: buffer, count: decompressedSize)
            }
            
            return nil
        }
    }
    
    /**
     * ZIPファイル内のファイルエントリを表す構造体
     */
    private struct ZipEntry {
        let filename: String           // ファイル名
        let localHeaderOffset: Int     // Local File Headerのオフセット位置
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
