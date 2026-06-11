//
//  ReadingHistoryManager.swift
//  coverZipViewer
//
//  LRU ベースの読書位置履歴管理
//

import Foundation

struct FileReadingHistory: Codable {
    let filename: String           // ZIPファイル名（拡張子除く、パス除く）
    let lastPageNumber: Int        // 最後に読んでいたページ番号
    let lastAccessDate: Date       // 最終アクセス日時
    let viewMode: String           // 表示モード（"single"/"spread"/"auto"）
    let spreadPairOffset: Int      // 見開きペアリングオフセット
    let isRightToLeftReading: Bool? // 綴じ方向（nilの場合は履歴なし = 既定に従う）
}

final class ReadingHistoryManager {
    static let shared = ReadingHistoryManager()

    private let maxHistoryCount = 100
    private let saveDebounceInterval: TimeInterval = 0.5
    private let defaults: UserDefaults

    // 直近の保存内容（デバウンス中の永続化待ち分）
    private var pendingHistory: FileReadingHistory?
    private var pendingSaveTimer: Timer?

    private init() {
        if let shared = UserDefaults(suiteName: CZAppGroup.identifier) {
            self.defaults = shared
        } else {
            self.defaults = .standard
        }
        // デフォルト設定を登録
        defaults.register(defaults: [
            CZSettingsKeys.readingHistoryEnabled: true
        ])
    }
    
    var isEnabled: Bool {
        get { defaults.bool(forKey: CZSettingsKeys.readingHistoryEnabled) }
        set { defaults.set(newValue, forKey: CZSettingsKeys.readingHistoryEnabled) }
    }
    
    /// ZIPファイルの読書位置を保存（実際の永続化は0.5秒デバウンス後に行う）
    func saveReadingPosition(filename: String, page: Int, viewMode: String, spreadPairOffset: Int, isRightToLeftReading: Bool) {
        guard isEnabled else { return }

        let normalizedFilename = normalizeFilename(filename)
        guard !normalizedFilename.isEmpty, page > 0 else { return }

        pendingHistory = FileReadingHistory(
            filename: normalizedFilename,
            lastPageNumber: page,
            lastAccessDate: Date(),
            viewMode: viewMode,
            spreadPairOffset: spreadPairOffset,
            isRightToLeftReading: isRightToLeftReading
        )

        pendingSaveTimer?.invalidate()
        let timer = Timer(timeInterval: saveDebounceInterval, repeats: false) { [weak self] _ in
            self?.flush()
        }
        pendingSaveTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// 保留中の読書位置を即座に永続化する（ビュー非表示時・解放時に呼ぶ）
    func flush() {
        pendingSaveTimer?.invalidate()
        pendingSaveTimer = nil

        guard let pending = pendingHistory else { return }
        pendingHistory = nil

        // 別プロセスの書き込みを上書きしないよう、直前に再読込してからマージする
        var histories = loadAllHistories()
        histories.removeAll { $0.filename == pending.filename }
        histories.insert(pending, at: 0)

        if histories.count > maxHistoryCount {
            histories = Array(histories.prefix(maxHistoryCount))
        }

        saveAllHistories(histories)

        NSLog("[ReadingHistory] Saved: %@ page %d viewMode %@ offset %d rtl %d", pending.filename, pending.lastPageNumber, pending.viewMode, pending.spreadPairOffset, pending.isRightToLeftReading ?? false)
    }

    /// ZIPファイルの前回読書位置を取得
    func loadReadingPosition(filename: String) -> (page: Int, viewMode: String, spreadPairOffset: Int, isRightToLeftReading: Bool?)? {
        guard isEnabled else { return nil }

        let normalizedFilename = normalizeFilename(filename)
        guard !normalizedFilename.isEmpty else { return nil }

        // 永続化前の保留中の値があればそちらを優先する
        if let pending = pendingHistory, pending.filename == normalizedFilename {
            NSLog("[ReadingHistory] Loaded (pending): %@ page %d viewMode %@ offset %d rtl %@", pending.filename, pending.lastPageNumber, pending.viewMode, pending.spreadPairOffset, pending.isRightToLeftReading?.description ?? "nil")
            return (page: pending.lastPageNumber, viewMode: pending.viewMode, spreadPairOffset: pending.spreadPairOffset, isRightToLeftReading: pending.isRightToLeftReading)
        }

        let histories = loadAllHistories()

        if let history = histories.first(where: { $0.filename == normalizedFilename }) {
            NSLog("[ReadingHistory] Loaded: %@ page %d viewMode %@ offset %d rtl %@", normalizedFilename, history.lastPageNumber, history.viewMode, history.spreadPairOffset, history.isRightToLeftReading?.description ?? "nil")
            return (page: history.lastPageNumber, viewMode: history.viewMode, spreadPairOffset: history.spreadPairOffset, isRightToLeftReading: history.isRightToLeftReading)
        }

        return nil
    }
    
    /// 履歴を全てクリア
    func clearAllHistory() {
        defaults.removeObject(forKey: CZSettingsKeys.readingHistoryData)
        NSLog("[ReadingHistory] All history cleared")
    }
    
    /// 履歴の件数を取得
    func getHistoryCount() -> Int {
        return loadAllHistories().count
    }
    
    // MARK: - 非公開メソッド
    
    private func normalizeFilename(_ filename: String) -> String {
        // パスからファイル名のみを抽出
        let name = URL(fileURLWithPath: filename).lastPathComponent
        // 拡張子を除去
        let nameWithoutExtension = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        return nameWithoutExtension
    }
    
    private func loadAllHistories() -> [FileReadingHistory] {
        guard let data = defaults.data(forKey: CZSettingsKeys.readingHistoryData) else {
            return []
        }
        
        do {
            return try JSONDecoder().decode([FileReadingHistory].self, from: data)
        } catch {
            NSLog("[ReadingHistory] Failed to load histories: %@", error.localizedDescription)
            // 破損したデータの場合は空配列を返す
            return []
        }
    }
    
    private func saveAllHistories(_ histories: [FileReadingHistory]) {
        do {
            let data = try JSONEncoder().encode(histories)
            defaults.set(data, forKey: CZSettingsKeys.readingHistoryData)
        } catch {
            NSLog("[ReadingHistory] Failed to save histories: %@", error.localizedDescription)
        }
    }
}