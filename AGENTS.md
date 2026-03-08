# AGENTS.md — CoverZip リポジトリ向けガードレールと運用指針

本ドキュメントは、エージェント／自動化ツール／新規コントリビュータが本リポジトリで作業する際の前提・禁止事項・変更方針を明文化したものです。安全かつ一貫した変更のために必ず参照してください。

## 目的と範囲
- 目的: 既存仕様を壊さずに機能追加・改善・保守を行うための共通ルールを提供する。
- 範囲: アプリ本体 `CoverZip`、Quick Look プレビュー拡張 `coverZipViewer`、サムネイル拡張 `coverZipExtension`、共有ユーティリティ `Shared`。

## プロジェクト構成と役割
- `CoverZip` (macOS App)
  - 設定ウィンドウ（SwiftUI）とファイルルーティングの中枢。
  - エントリ: `CoverZip/CoverZipApp.swift`（設定画面）、`CoverZip/AppDelegate.swift`（ファイルオープン・ルーティング）。
  - 「ZIPを開く…」メニューは常に内蔵ビューアを使用。
- `coverZipViewer` (Quick Look プレビュー拡張)
  - ZIP 内画像の閲覧 UI（単ページ/見開き/自動、右綴じ/左綴じ、ページ送りアニメ、スライドショー、履歴など）。
  - 操作方法: マウスクリック、キーボード、スクロールホイール対応。
  - 主要ファイル: `coverZipViewer/PreviewViewController.swift`、`coverZipViewer/ImageManager.swift`、`coverZipViewer/ReadingHistoryManager.swift`、`coverZipViewer/ThumbnailStripView.swift`、`coverZipViewer/ThumbnailCollectionViewItem.swift`、`coverZipViewer/Base.lproj/PreviewViewController.xib`。
- `coverZipExtension` (サムネイル拡張)
  - ZIP の先頭画像からサムネイル生成。
  - 主要ファイル: `coverZipExtension/ThumbnailProvider.swift`。
- `Shared`
  - 共有ユーティリティ群（ZIP 解析、自然順ソート、設定キー定義等）。
  - 主要ファイル: `Shared/ZipCore.swift`、`Shared/NaturalSort.swift`、`Shared/ImageFileFilter.swift`、`Shared/SettingsKeys.swift`。

## 共有設定と App Group
- App Group は `Shared/SettingsKeys.swift` の `CZAppGroup.identifier` に定義: `group.com.dmng.CoverZip`。
- 設定キーは `Shared/SettingsKeys.swift` に集約。アプリ・拡張とも同キー/同グループを利用。
- 設定 UI/保存: アプリ側は `CoverZip/Views/*` + `CoverZip/Services/AppSettings.swift`。拡張側は `coverZipViewer/Settings.swift`。

## ファイルルーティング仕様（重要）
- 設定は App Group UserDefaults（`CZSettingsKeys.routingSettingsData`）に保存する（`CoverZip/Models/KeywordSettings.swift`）。
- マッチングは先勝ち。`contains` は大文字小文字無視、`wildcard` は `*`/`?`、`regex` は NSRegularExpression（無効時は contains フォールバック）。

## 内蔵ビューアと拡張の連携
- アプリ側の内蔵ビューア: `CoverZip/Services/InternalViewer.swift`（`QLPreviewView` をウィンドウに埋め込み）。
- キー入力処理は `KeyForwardingView`（First Responder 専用の薄いビュー）で受け取り、`CZPreviewSessionCommand`（`goForwardPage` / `goBackwardPage`）を分散通知で送信してページ送りを駆動（正式: `QLPreviewInputDriver`）。
- `QLPreviewView` 自体を First Responder にしない（クローズ時の解放競合を回避）。
- クローズ時は OS の標準解放順序（`shouldCloseWithWindow = true`）に委ね、独自のビュー破棄は行わない。
- Context menu items (reading direction / view mode / spread offset / thumbnail strip visibility / animation / slideshow) are unified between the app-side internal viewer and Quick Look viewer via shared menu definitions.
- Runtime menu operations from the internal viewer are propagated to the Quick Look viewer via distributed session-command notifications (not direct shared-UserDefaults writes per operation).

## 実装ポリシー（変更方針）
- 変更は最小限・局所的・既存スタイルに合わせる。無関係な最適化や一括リネームは禁止。
- 仕様の単一責務を維持（ルーティングは App、画像表示は Viewer、ZIP 処理は Shared）。
- 共有キーや App Group を変更しない。必要なら合意の上で全ターゲット整合を取る。
- ログは既存の `NSLog` を用い、過剰出力は避ける（デバッグ時のみ詳細）。

## 禁止・注意事項（Danger Zone）
- App Group（`group.com.dmng.CoverZip`）や `CZSettingsKeys` の値を勝手に変更しない。
- Info.plist / Entitlements の権限・グループ設定を勝手に変更しない。
- ZIP コア（`Shared/ZipCore.swift`）を外部ライブラリに置換しない（合意がある場合を除く）。
- 共有設定の保存先を勝手に移動しない（UserDefaults/App Group 前提）。
- 破壊的コマンド（大規模削除・全体リフォーマット）を行わない。

## 既知の課題・改善候補（要合意）
1) ZIP 展開の制約（`Shared/ZipCore.swift`）
   - method 0/8 のみ、Zip64/暗号化非対応。8MB 固定バッファの伸長が必要なケースがある。
   - 改善にはメモリ安全性（上限/逐次解凍）と後方互換の検討が必要。

## テスト・検証の要点
- ルーティング: 複数の ZIP 名/パスで `contains`/`wildcard`/`regex` の動作を確認。`internal` 指定で内蔵ビューアに遷移すること。
- 内蔵ビューア: 左右クリック/キー/スクロールホイールでページ送り、右綴じ/左綴じ、単/見開き/自動の切り替え、スライドショー動作。
- 履歴: ZIP ごとの最終ページ・表示モード・綴じ方向・見開き補正が復元されること（App Group の UserDefaults に保存）。
- サムネイル: Finder でのサムネイル生成（異常系もログ確認）。

## Codex/Coding Agent 向け運用
- 複雑・複数工程の変更は `update_plan` を使って段階を明示。
- ファイル変更は `apply_patch` のみ使用。不要な再読込を避ける。
- この環境は通常 `workspace-write`/ネットワーク制限/`on-request` 承認。外部ネットワークや危険操作は事前に確認。
- テストやビルドが可能な場合、変更箇所に限定した検証を優先（不要な全体実行は避ける）。

## コーディングスタイル
- 既存の Swift スタイルに合わせる（意味のある命名、1文字変数回避、過剰な内蔵コメントは控える）。
- ドキュメントは必要最小限を更新（仕様変更時は本書/README/コメントいずれかへ反映）。
- ライセンス/ヘッダの追加は指示がある場合のみ。

## ビルド・動作の目安
- Xcode 14+（macOS 13+ 推奨）。Targets: `CoverZip`, `coverZipViewer`, `coverZipExtension`。
- App/Extensions の Entitlements に同一 App Group を設定。
- 初回起動時、`CoverZip` はルーティング設定が空の場合にサンプル値を UserDefaults へ投入する。

---
更新履歴:
- 2025-08-29 初版作成
- 2025-08-29 内蔵ビューアの重複解消（EmbeddedPreviewWindowController 削除）
- 2025-09-06 QLPreviewSmokeTest を正式化し `QLPreviewInputDriver` として採用
- 2025-09-06 内蔵ビューアの入力経路を `QLPreviewInputDriver` に統一（セーフ入力モード分岐を廃止）
- 2025-09-17 Preview Extension にマウスホイールスクロール対応を追加
- 2026-03-07 コンテキストメニュー定義を共通化し、内蔵ビューア→Preview Extension のセッション操作を分散通知で同期
- 2026-03-07 サムネイルリストの並び方向を綴じ方向に追従（左綴じ=左→右、右綴じ=右→左）
- 2026-03-07 右綴じかつ少ページ時のサムネイルを右端寄せで表示するよう調整
- 2026-03-07 見開き表示時はサムネイルを2件同時選択で同期するよう調整
- 2026-03-07 Refactored ZIP routing into `ZipRoutingService` and unified app resolution via `ApplicationResolver`
- 2026-03-07 Added `PreviewSessionStateStore` and `PreviewSessionCommandDispatcher` to reduce duplicated viewer/menu synchronization logic
- 2026-03-07 File routing settings are persisted in App Group UserDefaults; removed JSON-edit/save-button workflow
- 2026-03-07 Removed legacy `settings.json` migration/fallback path from routing settings load logic
- 2026-03-08 Replaced internal viewer key navigation click synthesis with distributed session commands (`goForwardPage` / `goBackwardPage`)
- 2026-03-08 Added internal-viewer context-menu shortcut glyphs and reassigned spread pairing shortcut to `Cmd+T` so Enter Full Screen uses `Cmd+F`
- 2026-03-08 Hardened full-screen shortcut override by reapplying `Cmd+F` across menu/window lifecycle notifications and title-based fallback matching
- 2026-03-08 Added NSUserKeyEquivalents fallback (`@f`) for localized/full-screen menu titles to keep Enter/Exit Full Screen on `Cmd+F`
- 2026-03-08 Removed full-screen shortcut override logic from app startup and returned Enter/Exit Full Screen shortcut handling to macOS defaults
