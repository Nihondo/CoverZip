# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

CoverZipは、四つの独立した機能を持つmacOSアプリケーションです：
1. **QuickLook Thumbnail Extension** - ZIPファイル内の先頭画像を使用したサムネイル生成
2. **QuickLook Preview Extension** - ZIPファイル内画像のフルスクリーンプレビューとページング機能
3. **ZIPファイルルーティングアプリケーション** - ファイル名キーワードマッチングによる外部アプリケーション自動起動
4. **内蔵ビューア** - QLPreviewViewを使用したメインアプリ内でのZIP画像表示機能

## アーキテクチャ

### 四つの独立したコンポーネント

#### 1. QuickLook Thumbnail Extension (`coverZipExtension/`)
- **ThumbnailProvider.swift** - `CZZip` でZIPから画像を抽出し、`CZImageUtilities` でアスペクト比計算・中央配置

#### 2. QuickLook Preview Extension (`coverZipViewer/`)
- **PreviewViewController.swift** - メインのプレビューUI制御（NSViewController）
- **ImageManager.swift** - 画像管理・ページング制御（遅延ロード実装）
  - メタデータ先行取得と必要時画像ロード
  - 元画像キャッシュ（最大10枚）とリサイズキャッシュ（最大20枚）
  - 隣接ページのバックグラウンドプリロード
- **ThumbnailStripView.swift** - サムネイルストリップUI（`ThumbnailResizeHandle`, `ThumbnailCollectionView`, `ThumbnailStripView`）
- **ThumbnailCollectionViewItem.swift** - サムネイルコレクションビューアイテム
- **ReadingHistoryManager.swift** - ZIP別の閲覧履歴管理（最終ページ、表示設定等）
- **Settings.swift** - 設定管理の軽量ラッパー（`CZSettings`へのアクセスを提供）

#### 3. ZIPファイルルーティングアプリケーション (`CoverZip/`)
- **CoverZipApp.swift** - SwiftUIアプリケーションエントリーポイント
- **AppDelegate.swift** - ファイルオープン処理（`processZipFile` → `ZipRoutingService.route()` → `handle()`）
- **Services/**
  - `ZipRoutingService.swift` - ルーティング判定と実行の分離（`RouteInvocationContext`, `RouteDecision`）
  - `KeywordMatcher.swift` - ファイル名ベースのマッチング
  - `AppLauncher.swift` - 外部アプリケーション起動
  - `ApplicationResolver.swift` - アプリ識別子（絶対パス/Bundle ID/アプリ名）からURLを解決
  - `ApplicationPicker.swift` - アプリケーション選択ダイアログ
  - `InternalViewer.swift` - QLPreviewView埋め込みビューア（設定同期・サムネイル表示等を統括）
  - `QLPreviewInputDriver.swift` - QLPreviewウィンドウとキーボード入力管理
  - `PreviewSessionCommandDispatcher.swift` - App/Extension間の分散通知を一元化
  - `PreviewSessionStateStore.swift` - セッション状態の読み出し（`PreviewSessionState`）
  - `AppSettings.swift` - SwiftUI用ObservableObjectラッパー（`CZSettings`を@Published経由で公開）
  - `SettingsFileManager.swift` - JSON設定ファイル管理
  - `FileOpenPanelService.swift` - ファイル選択ダイアログ
- **Commands/**
  - `FileMenuCommands.swift` - ファイルメニューコマンド（Cmd+O）
  - `ViewMenuCommands.swift` - ビューメニューコマンド（`ViewMenuState`, `ViewMenuCommands`）
- **Views/**
  - `RoutingSettingsView.swift` - ルーティング設定UI
  - `PreviewSettingsView.swift` - プレビュー設定UI
- **Models/KeywordSettings.swift** - JSON設定データモデル

#### 4. 共有ユーティリティ (`Shared/`)

**ZIP処理:**
- **ZipCore.swift** - 純Swift ZIP処理コア（Central Directory + DEFLATE展開）
- **NaturalSort.swift** - ファイル名の自然順ソート
- **ImageFileFilter.swift** - 画像ファイル判定

**設定管理:**
- **UnifiedAppSettings.swift** - 統一設定管理（`CZSettings`クラス、Single Source of Truth）
- **SettingsKeys.swift** - 共有設定キー・通知名・コマンド enum を集約
  - `CZSettingsKeys` - UserDefaults キー定義
  - `CZAppGroup` - App Group 識別子 (`group.com.dmng.CoverZip`)
  - `CZPreviewSessionCommand` - プレビューセッションコマンド enum
  - `CZDistributedNotifications` - App/Extension間分散通知名
  - `CZPreviewContextMenuLayout` / `CZPreviewContextMenuFactory` - コンテキストメニュー定義と生成
- **ViewModePreference.swift** - 表示モード enum の共有定義
- **UserDefaultsHelper.swift** - UserDefaults 統一アクセスポイント（`CZUserDefaults`）

**画像処理:**
- **ImageUtilities.swift** - 画像処理ユーティリティ（`CZImageUtilities`）
- **ImageIOOptions.swift** - 画像生成オプション

### App Extension制約への対応
- サンドボックス環境での動作保証
- メモリ使用量の最適化（8MBバッファ制限）
- App Group (`group.com.dmng.CoverZip`) による設定共有

## ビルドと開発

### ビルド方法
```bash
# Xcodeでプロジェクトを開く
open CoverZip.xcodeproj

# コマンドラインでビルド（コードサイン無効）
xcodebuild -project CoverZip.xcodeproj -scheme CoverZip build CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Extension単体のビルド
xcodebuild -project CoverZip.xcodeproj -scheme coverZipExtension build CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
xcodebuild -project CoverZip.xcodeproj -scheme coverZipViewer build CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

### Extensionのテストと開発
```bash
# QuickLook Extensionをリロード
qlmanage -r

# 特定のZIPファイルでサムネイル生成テスト
qlmanage -t path/to/test.zip

# ZIPファイルをプレビューで開く（Preview Extension）
qlmanage -p path/to/test.zip

# Extensionの登録状況確認
qlmanage -m | grep -i coverzip
pluginkit -m | grep -i coverzip
```

## 技術的詳細

### 主要な設計パターン

#### アプリケーション起動フロー

**ファイルドロップ/ダブルクリック時:**
```
ZIPファイル → AppDelegate.application(_:open:) →
processZipFile → ZipRoutingService.route(zipURL:invocationContext:.appLaunch) →
  RouteDecision.openInternalViewer → InternalViewer.shared.show() (継続実行)
  RouteDecision.openExternalApp   → AppLauncher → NSApplication.terminate
  RouteDecision.openDefaultApp    → AppLauncher → NSApplication.terminate
```

**メニューから開く時 (Cmd+O):**
```
FileMenuCommands → FileOpenPanelService.presentAndOpenZip() →
ZipRoutingService.route(invocationContext:.openPanelRouting) →
  常に RouteDecision.openInternalViewer → InternalViewer.shared.show()
```

#### App/Extension間通信アーキテクチャ

- **設定変更通知**: `PreviewSessionCommandDispatcher.postSettingsChanged()` → `CZDistributedNotifications.settingsChanged`
- **コマンド送信**: `PreviewSessionCommandDispatcher.post(command:boolValue:intValue:)` → `CZDistributedNotifications.previewSessionCommand`
- **受信側**: `PreviewViewController.handlePreviewSessionCommandNotification(_:)` で処理
- **コンテキストメニュー**: `CZPreviewContextMenuFactory.makeMenu(target:selectorForCommand:stateForCommand:)` で生成（App/Extension共通定義）

#### 内蔵ビューアアーキテクチャ（`QLPreviewInputDriver`）

- **キーボード入力**: `KeyForwardingView`（NSView サブクラス）をファーストレスポンダーとして配置し、左右キーを受信（ローカルイベントモニタは廃止）
- **クリック合成**: CGEvent で プレビュー領域の左右半分をクリックしてページ送りを駆動（アクセシビリティ権限が必要）
- **フォールバック**: QLPreviewView生成失敗時は `SimplePanelDataSource` 経由で共有パネル表示
- **ウィンドウ管理**: `retainedWindows` で強参照保持、OS標準のウィンドウクローズに委ねる
- **コンテキストメニュー**: `contextMenuProvider` クロージャ経由で `InternalViewer.makeContextMenu()` を呼び出し

#### Extension設定とApp Group
- **統一設定管理アーキテクチャ**:
  - **コア**: `CZSettings` (`Shared/UnifiedAppSettings.swift`) - 全設定の単一の真実の情報源
  - **Main App**: `AppSettingsWriter` (`CoverZip/Services/AppSettings.swift`) - SwiftUI用ObservableObjectラッパー
  - **Preview Extension**: `AppSettings` (`coverZipViewer/Settings.swift`) - 軽量ラッパー
  - **UserDefaults統一アクセス**: `CZUserDefaults.shared` (`Shared/UserDefaultsHelper.swift`)
- **セッション状態**: `PreviewSessionStateStore.loadState(resetSlideshowState:)` で一括読み出し

#### ZIP処理アーキテクチャ
- **コアエンジン**: `Shared/ZipCore.swift` - 純Swift実装、Foundation/Compressionのみ使用
- **対応圧縮方式**: DEFLATE（方式8）と非圧縮（方式0）
- **メモリ効率**: 8MBバッファによる制御されたメモリ使用
- **遅延ロードAPI**:
  - `imageEntryInfoList(from:)` - メタデータのみを高速取得
  - `extractImageData(from:entryInfo:)` - 個別の画像データを必要時に抽出
  - `imageEntries(from:)` - 全画像を一括取得（サムネイル生成等で使用）
- **自然順ソート**: `NaturalSort.lessFilename()` による数値認識ソート（全APIで一貫）

### QuickLook Preview Extension の機能

#### 高度な表示機能
- **表示モード**: 単ページ/見開き/自動（画像サイズに応じた判定）
- **読書方向**: 右綴じ/左綴じ対応
- **ページ送りアニメーション**: 設定可能なトランジション効果
- **スライドショー機能**: 自動ページ送り（新規セッション開始時は自動リセット）
- **サムネイルストリップ**: `ThumbnailStripView` によるページ一覧表示・リサイズ可能
- **操作方法**: マウスクリック、キーボード、スクロールホイール対応

#### 履歴機能
- **ZIP別履歴**: `ReadingHistoryManager.swift`による個別管理
- **保存データ**: 最終ページ、表示モード、見開き設定、読み方向
- **App Group共有**: 内蔵ビューアとの履歴同期

## ルーティング設定

### 保存先
App Group UserDefaults の `CZSettingsKeys.routingSettingsData` キーに JSON エンコードで保存（`KeywordSettings.save()` / `load()`）。`settings.json` ファイルの読み込みパスは廃止済み。

### データモデル（配列ベース）
```json
{
  "rules": [
    {
      "id": "<UUID>",
      "keyword": "コミック",
      "type": "filename",
      "application": "/Applications/Foo.app",
      "matchMode": "contains"
    },
    {
      "id": "<UUID>",
      "keyword": "vol*",
      "type": "filename",
      "application": "internal",
      "matchMode": "wildcard"
    }
  ],
  "defaultApplication": "/Applications/Archive Utility.app"
}
```

### マッチング方式（`MatchMode`）
- **contains** / **startsWith** / **endsWith**: 文字列検索（大文字小文字無視）
- **wildcard**: `*` / `?` 対応
- **regex**: NSRegularExpression（無効時は contains フォールバック）

### アプリケーション指定（`application` フィールド）
- **"internal"**: 内蔵ビューアで表示（継続実行）
- **絶対パス** (`/Applications/Foo.app`): 直接使用（保存時に `ApplicationResolver` で解決済み）
- アプリ名 / Bundle ID は `ApplicationResolver.resolveApplicationURL(from:)` で絶対パスに解決してから保存する

## 開発時の注意点

### 共有設定の管理
- App Group (`group.com.dmng.CoverZip`) を必ず使用
- 設定キーは `Shared/SettingsKeys.swift` に集約
- **新規設定の追加手順**:
  1. `Shared/SettingsKeys.swift` の `CZSettingsKeys` にキーを追加
  2. `Shared/UnifiedAppSettings.swift` の `CZSettings` にプロパティを追加
  3. 必要に応じてラッパー（`AppSettingsWriter` / `AppSettings`）にも追加
- **UserDefaults直接アクセス**: `CZUserDefaults.shared` を使用

### コンテキストメニューの拡張
- `CZPreviewContextMenuLayout.entries` にエントリを追加
- `CZPreviewSessionCommand` に対応コマンドを追加
- App側（`InternalViewer`）とExtension側（`PreviewViewController`）双方に `selector(for:)` / `menuState(for:)` を実装

### ZIP処理の制約
- **対応圧縮方式**: DEFLATE（方式8）と非圧縮（方式0）のみ
- **未対応**: Zip64、暗号化ZIP、その他の圧縮方式
- **メモリ効率**: 8MBバッファによる制御されたメモリ使用

## システム要件

- **macOS**: 11.0 (Big Sur) 以降
- **アーキテクチャ**: Universal Binary (Intel x86_64 + Apple Silicon arm64)
- **開発環境**: Xcode 14.0 以降
- **権限**: アクセシビリティ権限（内蔵ビューアのキー合成機能で使用）

## 参考資料

- **AGENTS.md**: エージェント/自動化ツール向けのガードレールと運用指針
- **README.md**: ユーザー向けの使用方法と機能説明
- **wiki-ja/**: 日本語での詳細技術ドキュメント
