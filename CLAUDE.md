# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

CoverZipは、四つの独立した機能を持つmacOSアプリケーションです：
1. **QuickLook Thumbnail Extension** - ZIP/RAR系アーカイブ内の表紙画像を使用したサムネイル生成
2. **QuickLook Preview Extension** - ZIP/RAR系アーカイブ内画像のフルスクリーンプレビューとページング機能
3. **アーカイブルーティングアプリケーション** - ファイル名キーワードマッチングによる外部アプリケーション自動起動
4. **内蔵ビューア** - QLPreviewViewを使用したメインアプリ内でのアーカイブ画像表示機能

## アーキテクチャ

### 四つの独立したコンポーネント

#### 1. QuickLook Thumbnail Extension (`coverZipExtension/`)
- **ThumbnailProvider.swift** - `CZArchiveKind` でZIP/RARを判定し、`CZZip` / `CZRar` で表紙画像を抽出、`CZImageUtilities` でアスペクト比計算・中央配置

#### 2. QuickLook Preview Extension (`coverZipViewer/`)
- **PreviewViewController.swift** - メインのプレビューUI制御（NSViewController）
- **PageProgressBarView.swift** - 画像に重ねて表示するページ進捗バー（`NSControl`）。カーソルが画像下端の帯（`pagerHoverBandHeight`）に入るとフェード表示され、クリック/ドラッグでページシーク可能。旧来のスライダー/ページラベルUIはこのオーバーレイに役割移行済み（値モデルとしては `pageSlider` を保持するが非表示固定）
- **ImageManager.swift** - 画像管理・ページング制御（遅延ロード実装）
  - メタデータ先行取得と必要時画像ロード
  - 元画像キャッシュ（最大10枚）とリサイズキャッシュ（最大20枚）
  - 隣接ページのバックグラウンドプリロード
  - `ThumbnailImageProviding` に準拠し、256px基準の tiny ティアキャッシュ（最大200件、LRU）をサムネイルストリップとメイン表示の白ページプレースホルダで共有（重複デコード排除）
  - `ImageEntrySource` プロトコル経由でZIP/RAR/フォルダの各データソースを同一ロジックで扱う（詳細は「アーカイブ処理アーキテクチャ」「フォルダQuickLook対応」参照）
- **ImageEntrySource.swift** - `ImageManager` が参照する画像データソースの抽象化（`ZipImageEntrySource` / `RarImageEntrySource` / `FolderImageEntrySource`）
- **ThumbnailStripView.swift** - サムネイルストリップUI（`ThumbnailResizeHandle`, `ThumbnailCollectionView`, `ThumbnailStripView`）。サムネイル画像は `thumbnailProvider`（`ImageManager`）の tiny ティアキャッシュに委譲し、独自のデコード経路は持たない
- **ThumbnailCollectionViewItem.swift** - サムネイルコレクションビューアイテム
- **ReadingHistoryManager.swift** - アーカイブ/フォルダ別の閲覧履歴管理（最終ページ、表示設定等）
- **Settings.swift** - 設定管理の軽量ラッパー（`CZSettings`へのアクセスを提供）

#### 3. アーカイブルーティングアプリケーション (`CoverZip/`)
- **CoverZipApp.swift** - SwiftUIアプリケーションエントリーポイント
- **AppDelegate.swift** - ファイルオープン処理（`processZipFile` → `ZipRoutingService.route()` → `handle()`）
- **Services/**
  - `ZipRoutingService.swift` - ルーティング判定と実行の分離（`RouteInvocationContext`, `RouteDecision`）
  - `KeywordMatcher.swift` - ファイル名・フォルダ名・拡張子ベースのマッチング（フォルダ名指定時はルートまでの全祖先フォルダを対象）
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

**アーカイブ処理:**
- **ArchiveKind.swift** - 拡張子とマジックナンバーによるZIP/RAR判定（`.cbr` は実体ZIPの場合があるためデコード直前はマジックナンバー優先）
- **CoverSelection.swift** - ZIP/RARで共有する表紙候補選定（cover/front/表紙/00/001）とImageIOサムネイル生成
- **ZipCore.swift** - 純Swift ZIP処理コア（Central Directory + DEFLATE展開）
- **RarCore.swift** - Unrar.swift を利用したRAR画像エントリ列挙・抽出。`Archive` はスレッド非安全のため抽出ごとに開き直す
- **NaturalSort.swift** - ファイル名の自然順ソート
- **ImageFileFilter.swift** - 画像ファイル判定

**フォルダ処理:**
- **FolderCore.swift** - フォルダ内画像の再帰列挙（`CZFolder`）。ZIP解凍を伴わないフォルダQuickLook対応で使用（詳細は「フォルダQuickLook対応」参照）

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

# 特定のアーカイブファイルでサムネイル生成テスト
qlmanage -t path/to/test.zip
qlmanage -t path/to/test.rar

# アーカイブファイルをプレビューで開く（Preview Extension）
qlmanage -p path/to/test.zip
qlmanage -p path/to/test.cbr

# Extensionの登録状況確認
qlmanage -m | grep -i coverzip
pluginkit -m | grep -i coverzip
```

## 技術的詳細

### 主要な設計パターン

#### アプリケーション起動フロー

Define the settings UI with a SwiftUI `Settings` scene, disable its state restoration, and present it only through `openSettings()` from Cmd+, or the application menu. Do not use a general-purpose `Window` scene for settings because document-launch activation can present it automatically.

**ファイルドロップ/ダブルクリック時:**
```
ZIP/RAR系アーカイブ/フォルダ → AppDelegate.application(_:open:) →
processZipFile → ZipRoutingService.route(zipURL:invocationContext:.appLaunch) →
  （フォルダ・パッケージ以外の場合は常に openInternalViewer）
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
- **Mouse input**: Across the viewer background except the thumbnail strip, use the window's horizontal midpoint to switch the cursor and click-based page navigation direction.
- **ページ移動経路**: 矢印キー/Space は `PreviewSessionCommandDispatcher` から `CZPreviewSessionCommand.goForwardPage/goBackwardPage` を送信し、`PreviewViewController.performPageNavigation(forward:)` で処理
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

#### アーカイブ処理アーキテクチャ
- **種別判定**: `Shared/ArchiveKind.swift` - 拡張子でルーティング入口を判定し、デコード直前はマジックナンバーでZIP/RAR実体を判定
- **ZIPコアエンジン**: `Shared/ZipCore.swift` - 純Swift実装、Foundation/Compressionのみ使用
- **RARコアエンジン**: `Shared/RarCore.swift` - SwiftPM依存 `mtgto/Unrar.swift` を使用。Unrar公式C++ソース由来のためRAR5対応だが、マルチボリュームRARは非対応
- **表紙選定**: `Shared/CoverSelection.swift` - ZIP/RAR共通の表紙候補選定とサムネイル生成
- **対応圧縮方式**: DEFLATE（方式8）と非圧縮（方式0）
- **メモリ効率**: ZIPは8MBバッファによる制御されたメモリ使用。RARはQuickLook拡張内での過大展開を避けるため、1画像の展開後サイズ上限を `CZRar.maxExtractedImageBytes` で制御
- **遅延ロードAPI**:
  - `imageEntryInfoList(from:)` - メタデータのみを高速取得
  - `extractImageData(from:entryInfo:)` - 個別の画像データを必要時に抽出
  - `imageEntries(from:)` - 全画像を一括取得（サムネイル生成等で使用）
- **自然順ソート**: `NaturalSort.lessFilename()` による数値認識ソート（全APIで一貫）

#### フォルダQuickLook対応
ZIPを解凍せず、フォルダ内の画像をZIPプレビューと同一のUI・ロジックで表示する機能。

- **対象範囲**: QuickLook Preview Extension（`coverZipViewer/`）と内蔵ビューアのみ。QuickLook Thumbnail Extension（`coverZipExtension/`）は非対応のまま（Finderの全フォルダアイコンを乗っ取らないための意図的な制限）
- **有効化**: `coverZipViewer/Info.plist` の `QLSupportedContentTypes` に `public.folder` を追加（`coverZipExtension/Info.plist` には追加しない）
- **データソース抽象化**: `ImageManager` は `entrySource: ImageEntrySource?` を介してZIP（`ZipImageEntrySource`）・RAR（`RarImageEntrySource`）・フォルダ（`FolderImageEntrySource`）を同一のインデックスベースAPI（`count` / `filename(at:)` / `imageData(at:)`）で扱う。`loadImages(from:)` がURLの `isDirectoryKey` と `CZArchiveKind.detect(at:)` で分岐する
- **列挙ロジック**: `CZFolder.imageEntryList(from:)` はサブフォルダを再帰的に列挙し（symlinkは辿らない、パッケージ内部は除外）、`ImageFileFilter.isImagePath` で画像のみ抽出。ソートは lastPathComponent 基準の自然順を第1キー、相対パス全体を第2キー（タイブレーク）として同名衝突時も順序を決定的にする
- **画像0枚のフォルダ**: `PreviewViewController.preparePreviewOfFile` がエラーをthrowし、システム標準のフォルダプレビューに委譲する（ZIPの場合は従来どおり `displayNoImagesMessage()` を表示）
- **メインアプリ側のルーティング**: `ZipRoutingService.route()` はアーカイブ拡張子判定より前にフォルダ（パッケージを除く）を検出し、常に `.openInternalViewer` を返す。ZIP/CBZ/RAR/CBRはキーワードルーティング対象になる。`CoverZip/Info.plist` の `CFBundleDocumentTypes` に `public.folder`（`LSHandlerRank=None`）を追加し、フォルダのDockドロップ等から内蔵ビューアで開けるようにしている
- **履歴**: `ReadingHistoryManager` はファイル名basenameをキーにするため、同名の `X.zip` とフォルダ `X` は読書履歴を共有する（意図的な仕様）

### QuickLook Preview Extension の機能

#### 高度な表示機能
- **表示モード**: 単ページ/見開き/自動（画像サイズに応じた判定）
- **読書方向**: 右綴じ/左綴じ対応
- **ページ送りアニメーション**: 設定可能なトランジション効果
- **スライドショー機能**: 自動ページ送り（新規セッション開始時は自動リセット）
- **サムネイルストリップ**: `ThumbnailStripView` によるページ一覧表示・リサイズ可能
- **プレースホルダ表示**: 通常/低解像度画像の準備が整うまでは `ImageManager` の tiny ティアキャッシュ（256px基準）があればそれを拡大表示し、無ければ白ページを表示
- **操作方法**: マウスクリック、キーボード、スクロールホイール対応

#### 履歴機能
- **アーカイブ別履歴**: `ReadingHistoryManager.swift`による個別管理
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

### マッチング対象（`type` フィールド）
- **filename**: アーカイブファイル名（拡張子除去済み）
- **pathname**: アーカイブファイルの全祖先フォルダ名（ルートまで）- いずれか1つにマッチすれば成功。近い側（親）から先に検索する
- **fileExtension**: アーカイブファイルの拡張子

### マッチング方式（`MatchMode`）
- **contains** / **startsWith** / **endsWith**: 文字列検索（大文字小文字無視）
- **wildcard**: `*` / `?` 対応
- **regex**: NSRegularExpression（無効時は contains フォールバック）

### アプリケーション指定（`application` フィールド）
- **"internal"**: 内蔵ビューアで表示（継続実行）
- **絶対パス** (`/Applications/Foo.app`): 直接使用（保存時に `ApplicationResolver` で解決済み）
- アプリ名 / Bundle ID は `ApplicationResolver.resolveApplicationURL(from:)` で絶対パスに解決してから保存する

## Sparkle Updates

- Sparkle is linked only to the `CoverZip` app target, not to the Quick Look extensions or the key helper.
- `CoverZip/Info.plist` owns the Sparkle keys:
  - `SUFeedURL`: `https://products.desireforwealth.com/appcast/coverzip/appcast.xml`
  - `SUPublicEDKey`: replace `REPLACE_WITH_COVERZIP_SPARKLE_EDDSA_PUBLIC_KEY` with the CoverZip EdDSA public key before release.
  - `SUEnableAutomaticChecks`: enabled, with `SUScheduledCheckInterval` set to 24 hours.
- `CoverZip/Update/AppUpdateController.swift` wraps `SPUStandardUpdaterController` and exposes update state for SwiftUI.
- `CoverZip/Update/UpdateSettingsView.swift` provides the Settings > Update tab.
- Manual checks are available from Settings > Update and the app menu item `Check for Updates...`.

### Sparkle EdDSA Key

The EdDSA private key must be stored outside the repository, preferably in macOS Keychain with a secure backup.

- Public key: committed in `Info.plist` under `SUPublicEDKey`.
- Private key: do not commit it. Store a secure backup in the password manager.
- If the private key is lost, generate a new key pair with Sparkle `generate_keys`, update `SUPublicEDKey`, and publish a new release. Users on old builds may need one manual update.

### Release Process

1. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in project settings.
2. Archive with Developer ID Application signing, notarize, then create `CoverZip.zip`.
3. Create a GitHub Release with tag `v{MARKETING_VERSION}` and attach `CoverZip.zip`.
4. Generate and publish the Sparkle appcast for `coverzip` in the product site/appcast pipeline.

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

### アーカイブ処理の制約
- **対応圧縮方式**: DEFLATE（方式8）と非圧縮（方式0）のみ
- **ZIP未対応**: Zip64、暗号化ZIP、その他の圧縮方式
- **RAR未対応**: 暗号化RAR、マルチボリュームRAR。ソリッドRARは閲覧可能でもページ抽出が遅くなる場合がある
- **メモリ効率**: ZIPは8MBバッファで制御。RARは `CZRar.maxExtractedImageBytes` を超える単一エントリをスキップする

### フォルダ処理の制約
- **symlink**: 一切辿らない（ディレクトリsymlinkは列挙されず、ファイルsymlinkは `isRegularFile` 判定で除外）
- **パッケージ**: `.skipsPackageDescendants` によりフォルダ内のパッケージ（`.app` 等）配下は列挙しない
- **サムネイル非対応**: `coverZipExtension`（Thumbnail Extension）は `public.folder` を宣言していないため、Finder上でフォルダのサムネイルは変化しない

## システム要件

- **macOS**: 11.0 (Big Sur) 以降
- **アーキテクチャ**: Universal Binary (Intel x86_64 + Apple Silicon arm64)
- **開発環境**: Xcode 14.0 以降
- **権限**: 特別なアクセシビリティ権限は不要（内蔵ビューアのキー操作は分散コマンド経由）

## 参考資料

- **AGENTS.md**: エージェント/自動化ツール向けのガードレールと運用指針
- **README.md**: ユーザー向けの使用方法と機能説明
- **wiki-ja/**: 日本語での詳細技術ドキュメント
