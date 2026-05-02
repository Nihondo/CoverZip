// MARK: - AppUpdateController.swift
// Sparkleアップデータのシングルトンラッパー。

import Combine
import Sparkle

/// Sparkleのアップデート状態をSwiftUIへ公開するコントローラ。
@MainActor
final class AppUpdateController: ObservableObject {

    static let shared = AppUpdateController()

    let updater: SPUUpdater

    private let controller: SPUStandardUpdaterController

    /// 手動アップデートチェックが現在実行可能かどうか。
    @Published var canCheckForUpdates: Bool

    /// 最後にアップデート確認が完了した日時。
    @Published var lastUpdateCheckDate: Date?

    /// 起動時および定期アップデート確認を行うかどうか。
    @Published var isAutomaticCheckEnabled: Bool

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updater = controller.updater
        canCheckForUpdates = updater.canCheckForUpdates
        lastUpdateCheckDate = updater.lastUpdateCheckDate
        isAutomaticCheckEnabled = updater.automaticallyChecksForUpdates

        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)

        updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastUpdateCheckDate)
    }

    /// 手動アップデートチェックを開始する。
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// 起動時および定期アップデート確認の有効/無効を切り替える。
    func setAutomaticCheckEnabled(_ isEnabled: Bool) {
        updater.automaticallyChecksForUpdates = isEnabled
        isAutomaticCheckEnabled = isEnabled
    }
}
