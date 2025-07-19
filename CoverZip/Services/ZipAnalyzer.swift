//
//  ZipAnalyzer.swift
//  CoverZip
//
//  Created by Nihondo on 2025/07/19.
//

import Foundation

/**
 * ZIPファイルの内容解析を担当するクラス
 * ファイル名とパスの一覧を取得する機能を提供する
 */
class ZipAnalyzer {
    
    /**
     * ZIPファイル内の全ファイル名とパスを取得する
     * 
     * @param url ZIPファイルのURL
     * @return ファイル情報のリスト（取得失敗時は空配列）
     */
    static func analyzeZipContents(at url: URL) -> [ZipFileInfo] {
        do {
            let data = try Data(contentsOf: url)
            return parseZipFileList(data: data)
        } catch {
            NSLog("Error reading ZIP file: \(error)")
            return []
        }
    }
    
    /**
     * ZIPファイルデータを解析してファイル情報のリストを作成する
     * 
     * @param data ZIPファイルのバイナリデータ
     * @return ファイル情報のリスト
     */
    private static func parseZipFileList(data: Data) -> [ZipFileInfo] {
        guard let centralDirectoryOffset = findCentralDirectoryOffset(in: data) else {
            return []
        }
        
        return parseCentralDirectoryForFileList(data: data, offset: centralDirectoryOffset)
    }
    
    /**
     * ZIPファイル内のCentral Directoryの位置を検索する
     * End of Central Directory Record（EOCDR）から逆算して位置を特定
     * 
     * @param data ZIPファイルのバイナリデータ
     * @return Central Directoryの開始オフセット（見つからない場合はnil）
     */
    private static func findCentralDirectoryOffset(in data: Data) -> Int? {
        let eocdrSignature: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        
        let searchRange = max(0, data.count - 65536)
        for i in stride(from: data.count - 4, through: searchRange, by: -1) {
            if data.subdata(in: i..<i+4).elementsEqual(eocdrSignature) {
                let offsetBytes = data.subdata(in: i+16..<i+20)
                let offset = offsetBytes.withUnsafeBytes { $0.load(as: UInt32.self) }
                return Int(offset)
            }
        }
        
        return nil
    }
    
    /**
     * Central Directoryを解析してファイル情報のリストを作成する
     * 
     * @param data ZIPファイルのバイナリデータ
     * @param offset Central Directoryの開始オフセット
     * @return ファイル情報のリスト
     */
    private static func parseCentralDirectoryForFileList(data: Data, offset: Int) -> [ZipFileInfo] {
        var fileInfos: [ZipFileInfo] = []
        var currentOffset = offset
        
        while currentOffset < data.count - 4 {
            let signature = data.subdata(in: currentOffset..<currentOffset+4)
            let expectedSignature: [UInt8] = [0x50, 0x4b, 0x01, 0x02]
            
            if !signature.elementsEqual(expectedSignature) {
                break
            }
            
            let filenameLength = data.subdata(in: currentOffset+28..<currentOffset+30).withUnsafeBytes { $0.load(as: UInt16.self) }
            let extraFieldLength = data.subdata(in: currentOffset+30..<currentOffset+32).withUnsafeBytes { $0.load(as: UInt16.self) }
            let commentLength = data.subdata(in: currentOffset+32..<currentOffset+34).withUnsafeBytes { $0.load(as: UInt16.self) }
            
            let filenameData = data.subdata(in: currentOffset+46..<currentOffset+46+Int(filenameLength))
            let fullPath = String(data: filenameData, encoding: .utf8) ?? ""
            
            // ファイル名とディレクトリパスを分離
            let components = fullPath.split(separator: "/")
            let filename = components.last.map(String.init) ?? ""
            let directoryPath = components.dropLast().joined(separator: "/")
            
            // __MACOSX や隠しファイルは除外
            if !fullPath.contains("__MACOSX") && !filename.hasPrefix(".") && !filename.isEmpty {
                fileInfos.append(ZipFileInfo(
                    filename: filename,
                    directoryPath: directoryPath,
                    fullPath: fullPath
                ))
            }
            
            currentOffset += 46 + Int(filenameLength) + Int(extraFieldLength) + Int(commentLength)
        }
        
        return fileInfos
    }
}

/**
 * ZIPファイル内のファイル情報を表す構造体
 */
struct ZipFileInfo {
    let filename: String        // ファイル名のみ
    let directoryPath: String   // ディレクトリパス
    let fullPath: String        // フルパス（ファイル名含む）
}