//
//  ImageManager.swift
//  coverZipViewer
//
//  Created by Nihondo on 2025/08/24.
//

import Foundation
import AppKit
import Compression

/**
 * ZIPファイル内の画像エントリを表す構造体
 */
struct ImageEntry {
    let filename: String           // ファイル名
    let imageData: Data           // 画像データ
}

/**
 * ZIPファイル内のファイルエントリを表す構造体
 */
struct ZipEntry {
    let filename: String            // ファイル名
    let localHeaderOffset: Int      // Local File Headerのオフセット位置
    let compressedSize: Int         // Central Directory 記載の圧縮サイズ
    let generalPurposeFlag: UInt16  // 汎用フラグ（bit3: データディスクリプタ使用）
    let compressionMethod: UInt16   // 圧縮方式（0: store, 8: deflate）
}

/**
 * プレビュー用の画像管理クラス
 * ZIPファイル内の画像リストを管理し、ページング機能を提供する
 */
class ImageManager {
    
    private var imageEntries: [ImageEntry] = []
    private var currentIndex: Int = 0
    private var imageCache: [Int: NSImage] = [:]
    private let maxCacheSize: Int = 10
    private var memoryPressureObserver: NSObjectProtocol?
    // 見開きの左右組み合わせを1ページ分ずらすためのオフセット（0 or 1）
    private var spreadPairOffset: Int = 0
    
    /**
     * ZIPファイルから画像を読み込む
     * 
     * @param url ZIPファイルのURL
     * @return 読み込み成功時はtrue、失敗時はfalse
     */
    func loadImages(from url: URL) -> Bool {
        imageEntries = extractAllImagesFromZip(at: url)
        currentIndex = 0
        imageCache.removeAll()
        setupMemoryPressureMonitoring()
        return !imageEntries.isEmpty
    }
    
    /**
     * 現在の画像を取得する
     * 
     * @return 現在の画像データ（画像がない場合はnil）
     */
    func getCurrentImage() -> NSImage? {
        guard !imageEntries.isEmpty, currentIndex >= 0, currentIndex < imageEntries.count else {
            return nil
        }
        
        if let cachedImage = imageCache[currentIndex] {
            return cachedImage
        }
        
        let imageData = imageEntries[currentIndex].imageData
        guard let image = NSImage(data: imageData) else {
            return nil
        }
        
        cacheImage(image, at: currentIndex)
        return image
    }
    
    /**
     * 見開き用の画像を取得する（左右2ページ）
     * 
     * @param isRightToLeft 右から左読み（日本語）の場合はtrue
     * @return (左ページ画像, 右ページ画像)のタプル。片方がない場合はnilが入る
     */
    func getSpreadImages(isRightToLeft: Bool) -> (left: NSImage?, right: NSImage?) {
        guard !imageEntries.isEmpty else {
            return (nil, nil)
        }
        
        // 表紙（1ページ目）は常に単ページ
        if currentIndex == 0 {
            return (getCurrentImage(), nil)
        }
        
        let leftIndex: Int
        let rightIndex: Int
        // ペア判定の偶奇を、オフセットで反転可能にする
        let parity = (currentIndex + spreadPairOffset) % 2
        
        if isRightToLeft {
            // RTL: 左3-右2, 左5-右4...（奇数ページが左）
            if parity == 1 {
                // 偶数ページ（2, 4, 6...）の場合、右側に配置し、左側は次のページ
                leftIndex = currentIndex + 1
                rightIndex = currentIndex
            } else {
                // 奇数ページ（3, 5, 7...）の場合、左側に配置し、右側は前のページ
                leftIndex = currentIndex
                rightIndex = currentIndex - 1
            }
        } else {
            // LTR: 左2-右3, 左4-右5...（偶数ページが左）
            if parity == 1 {
                // 偶数ページ（2, 4, 6...）の場合、左側に配置し、右側は次のページ
                leftIndex = currentIndex
                rightIndex = currentIndex + 1
            } else {
                // 奇数ページ（3, 5, 7...）の場合、右側に配置し、左側は前のページ
                leftIndex = currentIndex - 1
                rightIndex = currentIndex
            }
        }
        
        let leftImage = getImageAtIndex(leftIndex)
        let rightImage = getImageAtIndex(rightIndex)
        
        return (leftImage, rightImage)
    }

    // 現在の見開きペアリングオフセットをトグル（0<->1）
    func toggleSpreadPairOffset() {
        spreadPairOffset = 1 - spreadPairOffset
    }

    func setSpreadPairOffset(_ value: Int) {
        spreadPairOffset = (value % 2 + 2) % 2
    }

    func getSpreadPairOffset() -> Int { spreadPairOffset }
    
    /**
     * 指定されたインデックスの画像を取得する
     * 
     * @param index 画像のインデックス
     * @return 画像データ（範囲外やエラーの場合はnil）
     */
    private func getImageAtIndex(_ index: Int) -> NSImage? {
        guard index >= 0, index < imageEntries.count else {
            return nil
        }
        
        if let cachedImage = imageCache[index] {
            return cachedImage
        }
        
        let imageData = imageEntries[index].imageData
        guard let image = NSImage(data: imageData) else {
            return nil
        }
        
        cacheImage(image, at: index)
        return image
    }
    
    /**
     * 現在の画像のファイル名を取得する
     * 
     * @return 現在の画像のファイル名（画像がない場合は空文字列）
     */
    func getCurrentImageName() -> String {
        guard !imageEntries.isEmpty, currentIndex >= 0, currentIndex < imageEntries.count else {
            return ""
        }
        
        return imageEntries[currentIndex].filename
    }
    
    /**
     * 次の画像に移動する
     * 
     * @param isSpreadMode 見開きモードの場合はtrue
     * @return 移動成功時はtrue、移動できない場合はfalse
     */
    func nextImage(isSpreadMode: Bool = false) -> Bool {
        guard !imageEntries.isEmpty else {
            return false
        }
        
        if isSpreadMode {
            // 見開きモードでは2ページずつ移動（表紙除く）
            if currentIndex == 0 {
                // 表紙から2ページ目へ
                guard currentIndex < imageEntries.count - 1 else { return false }
                currentIndex = 1
            } else {
                // 2ページずつ進む
                let nextIndex = currentIndex + 2
                guard nextIndex < imageEntries.count else { return false }
                currentIndex = nextIndex
            }
        } else {
            // 単ページモードでは1ページずつ
            guard currentIndex < imageEntries.count - 1 else { return false }
            currentIndex += 1
        }
        
        preloadAdjacentImages()
        return true
    }
    
    /**
     * 前の画像に移動する
     * 
     * @param isSpreadMode 見開きモードの場合はtrue
     * @return 移動成功時はtrue、移動できない場合はfalse
     */
    func previousImage(isSpreadMode: Bool = false) -> Bool {
        guard !imageEntries.isEmpty, currentIndex > 0 else {
            return false
        }
        
        if isSpreadMode {
            // 見開きモードでは2ページずつ移動
            if currentIndex == 1 {
                // 2ページ目から表紙へ
                currentIndex = 0
            } else {
                // 2ページずつ戻る
                let prevIndex = currentIndex - 2
                currentIndex = max(0, prevIndex)
            }
        } else {
            // 単ページモードでは1ページずつ
            currentIndex -= 1
        }
        
        preloadAdjacentImages()
        return true
    }
    
    /**
     * 画像の総数を取得する
     * 
     * @return 画像の総数
     */
    func getImageCount() -> Int {
        return imageEntries.count
    }
    
    /**
     * 現在のページ番号を取得する（1始まり）
     * 
     * @return 現在のページ番号
     */
    func getCurrentPageNumber() -> Int {
        return currentIndex + 1
    }

    /// 指定ページへ移動（1始まり）
    /// - Parameter page: 1...imageCount の範囲内で移動。範囲外は丸め込み。
    /// - Returns: 有効な画像が存在する場合にtrue
    func goToPage(_ page: Int) -> Bool {
        guard !imageEntries.isEmpty else { return false }
        let clamped = max(1, min(page, imageEntries.count))
        let newIndex = clamped - 1
        currentIndex = newIndex
        preloadAdjacentImages()
        return true
    }
    
    /**
     * 画像があるかどうかを確認する
     * 
     * @return 画像がある場合はtrue、ない場合はfalse
     */
    func hasImages() -> Bool {
        return !imageEntries.isEmpty
    }
    
    /**
     * 現在のページが表紙かどうかを判定する
     * 
     * @return 表紙の場合はtrue、それ以外はfalse
     */
    func isCoverPage() -> Bool {
        return currentIndex == 0
    }
    
    // MARK: - Cache Management Methods
    
    private func cacheImage(_ image: NSImage, at index: Int) {
        if imageCache.count >= maxCacheSize {
            removeOldestCachedImage()
        }
        imageCache[index] = image
    }
    
    private func removeOldestCachedImage() {
        guard !imageCache.isEmpty else { return }
        
        // 現在のインデックスから最も離れているキャッシュを削除
        let farthestIndex = imageCache.keys.max { abs($0 - currentIndex) < abs($1 - currentIndex) }
        if let indexToRemove = farthestIndex {
            imageCache.removeValue(forKey: indexToRemove)
        }
    }
    
    func preloadAdjacentImages() {
        let indicesToLoad = [currentIndex - 1, currentIndex + 1].filter { 
            $0 >= 0 && $0 < imageEntries.count && imageCache[$0] == nil 
        }
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            for index in indicesToLoad {
                self?.loadImageAtIndex(index)
            }
        }
    }
    
    private func loadImageAtIndex(_ index: Int) {
        guard index >= 0, index < imageEntries.count, imageCache[index] == nil else {
            return
        }
        
        let imageData = imageEntries[index].imageData
        if let image = NSImage(data: imageData) {
            DispatchQueue.main.async { [weak self] in
                self?.cacheImage(image, at: index)
            }
        }
    }
    
    // MARK: - Memory Management Methods
    
    private func setupMemoryPressureMonitoring() {
        removeMemoryPressureObserver()
        
        // App ExtensionではNSApplicationの通知を使用できないため、シンプルなキャッシュサイズ制限のみ実装
        // 必要に応じて、メモリ使用量を手動で監視する実装も可能
    }
    
    private func removeMemoryPressureObserver() {
        if let observer = memoryPressureObserver {
            NotificationCenter.default.removeObserver(observer)
            memoryPressureObserver = nil
        }
    }
    
    private func handleMemoryPressure() {
        // 現在の画像以外のキャッシュをクリア
        let currentImage = imageCache[currentIndex]
        imageCache.removeAll()
        
        if let image = currentImage {
            imageCache[currentIndex] = image
        }
    }
    
    func clearCache() {
        let currentImage = imageCache[currentIndex]
        imageCache.removeAll()
        
        if let image = currentImage {
            imageCache[currentIndex] = image
        }
    }
    
    deinit {
        removeMemoryPressureObserver()
    }
    
    // MARK: - ZIP Processing Methods
    
    /**
     * ZIPファイルから全ての画像ファイルを抽出する
     * 
     * @param url ZIPファイルのURL
     * @return 画像エントリの配列（見つからない場合は空配列）
     */
    private func extractAllImagesFromZip(at url: URL) -> [ImageEntry] {
        do {
            let data = try Data(contentsOf: url)
            return parseZipAndFindAllImages(data: data)
        } catch {
            NSLog("Error reading ZIP file: \(error)")
            return []
        }
    }
    
    /**
     * ZIPファイルデータを解析し、全ての画像ファイルを検索する
     * 
     * @param data ZIPファイルのバイナリデータ
     * @return 全ての画像ファイルのエントリ配列
     */
    private func parseZipAndFindAllImages(data: Data) -> [ImageEntry] {
        // ZIP Central Directory の検索
        guard let centralDirectoryOffset = findCentralDirectoryOffset(in: data) else {
            return []
        }
        
        // Central Directory からファイルエントリを読み取り
        let entries = parseCentralDirectory(data: data, offset: centralDirectoryOffset)
        
        // 全ての画像ファイルを抽出
        var imageEntries: [ImageEntry] = []
        for entry in entries {
            if isImageFile(filename: entry.filename) {
                if let imageData = extractFileData(data: data, entry: entry) {
                    imageEntries.append(ImageEntry(filename: entry.filename, imageData: imageData))
                }
            }
        }
        // ファイル名の自然順（数字は数値として比較）でソート
        imageEntries.sort { a, b in
            naturalLess((a.filename as NSString).lastPathComponent,
                        (b.filename as NSString).lastPathComponent)
        }
        return imageEntries
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
            
            // GP Flag / Compression Method / Sizes
            let gpFlag = data.subdata(in: currentOffset+8..<currentOffset+10).withUnsafeBytes { $0.load(as: UInt16.self) }
            let compMethod = data.subdata(in: currentOffset+10..<currentOffset+12).withUnsafeBytes { $0.load(as: UInt16.self) }
            let cdCompressed = data.subdata(in: currentOffset+20..<currentOffset+24).withUnsafeBytes { $0.load(as: UInt32.self) }
            // uncompressed size は今は未使用
            // let cdUncompressed = data.subdata(in: currentOffset+24..<currentOffset+28).withUnsafeBytes { $0.load(as: UInt32.self) }

            // ファイル名の長さを取得
            let filenameLength = data.subdata(in: currentOffset+28..<currentOffset+30).withUnsafeBytes { $0.load(as: UInt16.self) }
            let extraFieldLength = data.subdata(in: currentOffset+30..<currentOffset+32).withUnsafeBytes { $0.load(as: UInt16.self) }
            let commentLength = data.subdata(in: currentOffset+32..<currentOffset+34).withUnsafeBytes { $0.load(as: UInt16.self) }
            
            // ファイル名を取得
            let filenameData = data.subdata(in: currentOffset+46..<currentOffset+46+Int(filenameLength))
            let filename = String(data: filenameData, encoding: .utf8) ?? ""
            
            // Local File Header のオフセットを取得
            let localHeaderOffset = data.subdata(in: currentOffset+42..<currentOffset+46).withUnsafeBytes { $0.load(as: UInt32.self) }
            
            entries.append(ZipEntry(
                filename: filename,
                localHeaderOffset: Int(localHeaderOffset),
                compressedSize: Int(cdCompressed),
                generalPurposeFlag: gpFlag,
                compressionMethod: compMethod
            ))
            
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
        // ローカルヘッダの圧縮サイズ（bit3が立っている場合は0のことがある）
        let lhCompressed = data.subdata(in: offset+18..<offset+22).withUnsafeBytes { $0.load(as: UInt32.self) }
        // 圧縮方法（ローカルヘッダ優先だが、CDの値とも一致するはず）
        let compressionMethod = data.subdata(in: offset+8..<offset+10).withUnsafeBytes { $0.load(as: UInt16.self) }
        
        // ファイルデータの開始位置
        let fileDataOffset = offset + 30 + Int(filenameLength) + Int(extraFieldLength)
        // 使用する圧縮サイズを決定（Data Descriptor使用時はCDのサイズを使う）
        let useCompressedSize: Int
        if entry.generalPurposeFlag & 0x0008 != 0 { // bit3: Data Descriptor
            useCompressedSize = entry.compressedSize
        } else {
            useCompressedSize = Int(lhCompressed)
        }
        guard useCompressedSize > 0, fileDataOffset + useCompressedSize <= data.count else { return nil }
        let fileData = data.subdata(in: fileDataOffset..<(fileDataOffset + useCompressedSize))
        
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

    // MARK: - Natural sort by filename (numbers compared numerically)
    private enum Token: Equatable {
        case text(String)
        case number(Int, length: Int) // length keeps original digit count for tie-break
    }

    private func naturalLess(_ lhs: String, _ rhs: String) -> Bool {
        let lt = tokenize(lhs.lowercased())
        let rt = tokenize(rhs.lowercased())
        let n = min(lt.count, rt.count)
        for i in 0..<n {
            let a = lt[i]
            let b = rt[i]
            switch (a, b) {
            case let (.number(x, lx), .number(y, ly)):
                if x != y { return x < y }
                // same numeric value: shorter digit length comes first (e.g., 2 < 002)
                if lx != ly { return lx < ly }
            case let (.text(x), .text(y)):
                if x != y { return x < y }
            case (.number, .text):
                // numbers come before letters after equal prefix
                return true
            case (.text, .number):
                return false
            }
        }
        // All shared tokens equal; shorter wins, else fallback to simple compare
        if lt.count != rt.count { return lt.count < rt.count }
        return lhs.localizedCompare(rhs) == .orderedAscending
    }

    private func tokenize(_ s: String) -> [Token] {
        var tokens: [Token] = []
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch.isNumber {
                var j = i
                while j < s.endIndex, s[j].isNumber { j = s.index(after: j) }
                let substr = String(s[i..<j])
                let val = Int(substr) ?? 0
                tokens.append(.number(val, length: substr.count))
                i = j
            } else {
                var j = i
                while j < s.endIndex, !s[j].isNumber { j = s.index(after: j) }
                let substr = String(s[i..<j])
                tokens.append(.text(substr))
                i = j
            }
        }
        return tokens
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
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 8 * 1024 * 1024) // 8MB buffer
            defer { buffer.deallocate() }
            
            let decompressedSize = compression_decode_buffer(buffer, 8 * 1024 * 1024, bytes.bindMemory(to: UInt8.self).baseAddress!, compressedData.count, nil, COMPRESSION_ZLIB)
            
            if decompressedSize > 0 {
                return Data(bytes: buffer, count: decompressedSize)
            }
            
            return nil
        }
    }
}