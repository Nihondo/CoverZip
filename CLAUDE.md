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
- **ThumbnailProvider.swift** - QuickLookサムネイル拡張機能のエントリーポイント
- **ZipProcessor.swift** - ZIP処理専用クラス（現在はレガシー、Shared/ZipCore.swiftが推奨）

#### 2. QuickLook Preview Extension (`coverZipViewer/`)
- **PreviewViewController.swift** - メインのプレビューUI制御（NSViewController）
- **ImageManager.swift** - 画像管理・ページング制御（遅延ロード実装）
  - メタデータ先行取得と必要時画像ロード
  - 元画像キャッシュ（最大10枚）とリサイズキャッシュ（最大20枚）
  - 隣接ページのバックグラウンドプリロード
  - 表示サイズに最適化されたリサイズ処理
- **ReadingHistoryManager.swift** - ZIP別の閲覧履歴管理（最終ページ、表示設定等）
- **Settings.swift** - 設定管理（App Group共有）
- **Base.lproj/PreviewViewController.xib** - UI定義

#### 3. ZIPファイルルーティングアプリケーション (`CoverZip/`)
- **CoverZipApp.swift** - SwiftUIアプリケーションエントリーポイント
- **AppDelegate.swift** - ファイルオープン処理とルーティングロジック
- **Services/**
  - `KeywordMatcher.swift` - ファイル名ベースのマッチング
  - `AppLauncher.swift` - 外部アプリケーション起動
  - `SettingsFileManager.swift` - JSON設定管理
  - `AppSettings.swift` - App Group共有設定
  - `InternalViewer.swift` - QLPreviewView埋め込みビューア
  - `FileOpenPanelService.swift` - ファイル選択ダイアログ
- **Commands/FileMenuCommands.swift** - メニューコマンド（Cmd+O）
- **Views/**
  - `RoutingSettingsView.swift` - ルーティング設定UI
  - `PreviewSettingsView.swift` - プレビュー設定UI
- **Models/KeywordSettings.swift** - JSON設定データモデル

#### 4. 共有ユーティリティ (`Shared/`)
- **ZipCore.swift** - 純Swift ZIP処理コア（Central Directory + DEFLATE展開）
- **NaturalSort.swift** - ファイル名の自然順ソート
- **ImageFileFilter.swift** - 画像ファイル判定
- **SettingsKeys.swift** - 共有設定キー定義
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
ZIPファイル → AppDelegate:application:open:urls: → 
processZipFile → KeywordMatcher → "internal"判定 → InternalViewer.show() (継続実行)
                              → 外部アプリ判定 → AppLauncher → NSApplication.terminate
```

**メニューから開く時 (Cmd+O):**
```
FileMenuCommands → FileOpenPanelService.presentAndOpenZip() → 
InternalViewer.show() (常に内蔵ビューアで表示)
```

#### Extension設定とApp Group
- **App Group**: `group.com.dmng.CoverZip`（`Shared/SettingsKeys.swift`に定義）
- **共有設定**: 読み方向、表示モード、ページ送りアニメ、履歴データ等
- **設定クラス**: `AppSettings` (Main App) / `Settings` (Preview Extension)

#### ZIP処理アーキテクチャ
- **コアエンジン**: `Shared/ZipCore.swift` - 純Swift実装、Foundation/Compressionのみ使用
- **対応圧縮方式**: DEFLATE（方式8）と非圧縮（方式0）
- **メモリ効率**: 8MBバッファによる制御されたメモリ使用
- **画像抽出**: 表紙らしい名前の優先判定（cover/front/表紙/00*系）
- **遅延ロードAPI**:
  - `imageEntryInfoList(from:)` - メタデータのみを高速取得
  - `extractImageData(from:entryInfo:)` - 個別の画像データを必要時に抽出
  - `imageEntries(from:)` - 全画像を一括取得（サムネイル生成等で使用）
- **自然順ソート**: `NaturalSort.lessFilename()` による数値認識ソート（全APIで一貫）

### 内蔵ビューアの実装詳細

#### QLPreviewView 埋め込みアーキテクチャ
- **NSWindowベース**: 独立したウィンドウでQLPreviewViewを埋め込み
- **フォールバック機構**: QLPreviewView生成失敗時は共有パネル経由で表示
- **ウィンドウ管理**: 複数ウィンドウ対応とクリーンアップ処理

#### キーボードナビゲーション実装
- **イベントモニター**: NSEvent.addLocalMonitorForEventsでキー入力監視
- **合成クリック**: CGEventによるグローバルクリックイベント生成と NSApp.postEvent フォールバック
- **アクセシビリティ**: AXIsProcessTrusted()による権限チェック
- **座標変換**: ウィンドウ→スクリーン座標変換でプレビュー領域の左右半分をクリック

#### コンテキストメニュー機能
- **設定統合**: App Group共有設定の読み書き
- **動的メニュー**: 現在の設定値に基づく状態表示（右綴じ/左綴じ、表示モード等）
- **即時反映**: UserDefaults変更による設定の即時更新

### QuickLook Preview Extension の機能

#### 高度な表示機能
- **表示モード**: 単ページ/見開き/自動（画像サイズに応じた判定）
- **読書方向**: 右綴じ/左綴じ対応
- **ページ送りアニメーション**: 設定可能なトランジション効果
- **スライドショー機能**: 自動ページ送り
- **操作方法**: マウスクリック、キーボード、スクロールホイール対応
- **レスポンシブUI**: ウィンドウサイズに応じた UI 要素の動的調整

#### 遅延ロード方式による最適化
- **メタデータ先行取得**: `CZZip.imageEntryInfoList()` により画像のメタデータを即座に取得
- **必要時データロード**: 実際の画像データは表示時に `CZZip.extractImageData()` で取得
- **高速ページ送り**: 2ページ目以降への遷移が即座に可能（全画像読み込み待ちなし）
- **メモリ効率**: 必要な画像のみをメモリに保持、隣接ページのプリロード実装
- **リサイズキャッシュ**: 表示サイズに最適化された画像をキャッシュしパフォーマンス向上
- **自然順ソート一貫性**: メタデータ取得時も `NaturalSort.lessFilename()` で正しくソート

#### 履歴機能
- **ZIP別履歴**: `ReadingHistoryManager.swift`による個別管理
- **保存データ**: 最終ページ、表示モード、見開き設定、読み方向
- **App Group共有**: 内蔵ビューアとの履歴同期

## 設定ファイル（settings.json）

### 設定ファイルの階層
1. `~/Library/Application Support/CoverZip/settings.json` (優先)
2. アプリバンドル内の `settings.json`
3. デフォルト設定（空の keywords）

### JSON設定形式
```json
{
  "keywords": {
    "コミック": {
      "type": "filename",
      "application": "internal",
      "matchMode": "contains"
    },
    "vol*": {
      "type": "filename", 
      "application": "SimpleComicViewer.app",
      "matchMode": "wildcard"
    },
    "^backup_\\d+$": {
      "type": "pathname",
      "application": "Archive Utility.app", 
      "matchMode": "regex"
    }
  },
  "default": "Archive Utility.app"
}
```

### マッチング方式
- **contains**: 部分一致検索（大文字小文字無視）
- **wildcard**: ワイルドカード (`*`, `?`) 対応
- **regex**: NSRegularExpression による正規表現（無効時は contains フォールバック）

### アプリケーション指定
- **"internal"**: 内蔵ビューアで表示（継続実行）
- **アプリケーション名**: 外部アプリケーションで開く（自動終了）

## 開発時の注意点

### Extension の特徴
- QuickLook Extension（Thumbnail/Preview）は独立したプロセスで動作
- サンドボックス環境での制限
- メモリ使用量の制限（8MBバッファ）
- Preview ExtensionではNSViewController使用（フルUIコントロール）

### 共有設定の管理
- App Group (`group.com.dmng.CoverZip`) を必ず使用
- 設定キーは `Shared/SettingsKeys.swift` に集約
- Main App と Extension 間での設定同期に注意

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