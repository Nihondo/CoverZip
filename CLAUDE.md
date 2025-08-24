# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

CoverZipは、三つの独立した機能を持つmacOSアプリケーションです：
1. **QuickLook Thumbnail Extension** - ZIPファイル内の先頭画像を使用したサムネイル生成
2. **QuickLook Preview Extension** - ZIPファイル内画像のフルスクリーンプレビューとページング機能
3. **ZIPファイルルーティングアプリケーション** - ファイル名キーワードマッチングによる外部アプリケーション自動起動

## アーキテクチャ

### 三つの独立したコンポーネント

#### 1. QuickLook Thumbnail Extension (`coverZipExtension/`)
- **ThumbnailProvider.swift** - QuickLookサムネイル拡張機能のエントリーポイント
  - `QLThumbnailProvider`を継承したメインクラス
  - 画像の縦横比維持とスケーリング処理
  - `ZipProcessor`を呼び出してZIPファイル処理を委譲

- **ZipProcessor.swift** - ZIP処理専用クラス（純Swift実装）
  - ZIPファイルの解析（Central Directory + Local File Header）
  - DEFLATE圧縮データの展開（8MBバッファ）
  - 画像ファイルの検出と抽出
  - 外部ライブラリ不要、標準フレームワークのみ使用

#### 2. QuickLook Preview Extension (`coverZipViewer/`)
- **PreviewProvider.swift** / **PreviewViewController.swift** - QuickLookプレビュー拡張機能
  - フルスクリーンでのZIPファイル内画像表示
  - ページスライダーとページ番号表示
  - クリック・キーボードによるページ移動機能
  - RTL（右から左）読書方向対応
  - スライダー表示/非表示の動的制御

- **ImageManager.swift** - 画像管理とページング
  - ZIPファイル内の画像ファイル検出・読み込み
  - ページ移動機能（next/previous/goToPage）
  - 隣接画像の先読み機能

- **Settings.swift** - 設定管理（App Group共有）
  - 右から左の読書方向設定
  - スライダー表示閾値設定

#### 3. ZIPファイルルーティングアプリケーション (`CoverZip/`)
- **CoverZipApp.swift (AppDelegate)** - ファイル処理とアプリケーション制御
  - 複数のファイル開くメソッド実装（`application:openFile:`, `application:open:urls:`等）
  - ZIPファイル名でのキーワードマッチング実行
  - 外部アプリケーション起動後の自動終了機能
  - Settings sceneによるバックグラウンド動作

- **Services/KeywordMatcher.swift** - ファイル名ベースのマッチング
  - ZIPファイル名（拡張子除去）からキーワード抽出
  - `KeywordSettings`（JSON設定）に基づくアプリケーション決定
  - NSLog出力によるデバッグ情報提供

- **Services/AppLauncher.swift** - 外部アプリケーション起動
  - 一時ファイル作成とNSWorkspace経由での起動
  - デフォルトアプリケーション起動機能

- **Services/SettingsFileManager.swift** - JSON設定管理
  - 外部エディタでのsettings.json編集機能
  - Application Supportディレクトリでの設定ファイル管理

- **Models/KeywordSettings.swift** - 設定データモデル
  - JSON設定ファイルの読み込み・書き込み
  - キーワード→アプリケーション名のマッピング管理

### App Extension制約への対応
- サンドボックス環境での動作保証
- メモリ使用量の最適化（8MBバッファ制限）
- App Extensionプロセス分離への適合

### プロジェクト構造
- `CoverZip/` - SwiftUIベースのメインアプリケーション（Settings scene使用）
  - `CoverZipApp.swift` - AppDelegateによるファイル処理制御
  - `Services/` - ビジネスロジック層
    - `KeywordMatcher.swift` - ファイル名マッチング
    - `AppLauncher.swift` - 外部アプリ起動
    - `SettingsFileManager.swift` - 設定ファイル管理
    - `AppSettings.swift` - App Group共有設定
  - `Models/KeywordSettings.swift` - JSON設定データモデル
- `coverZipExtension/` - QuickLook Thumbnail Extension
  - `ThumbnailProvider.swift` - サムネイル生成エントリーポイント
  - `ZipProcessor.swift` - ZIP処理ロジック（純Swift実装）
  - `Info.plist` - Extension設定
- `coverZipViewer/` - QuickLook Preview Extension
  - `PreviewProvider.swift` - プレビューエントリーポイント
  - `PreviewViewController.swift` - プレビューUI制御（NSViewController）
  - `ImageManager.swift` - 画像管理・ページング制御
  - `Settings.swift` - 設定管理（App Group共有）
  - `Base.lproj/PreviewViewController.xib` - UI定義
  - `Info.plist` - Extension設定
- `CoverZipTests/` - Swift Testingベースのユニットテスト
- `CoverZipUITests/` - UI自動化テスト

## ビルドと開発

### ビルド方法
```bash
# Xcodeでプロジェクトを開く
open CoverZip.xcodeproj

# コマンドラインでビルド（コードサイン無効）
xcodebuild -project CoverZip.xcodeproj -scheme CoverZip build CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Extension単体のビルド（Thumbnail）
xcodebuild -project CoverZip.xcodeproj -target coverZipExtension build -configuration Debug CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Extension単体のビルド（Preview）
xcodebuild -project CoverZip.xcodeproj -target coverZipViewer build -configuration Debug CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

### Extensionのテスト
```bash
# QuickLook Extensionをリロード
qlmanage -r

# 特定のZIPファイルでサムネイル生成テスト
qlmanage -t path/to/test.zip

# ZIPファイルをプレビューで開く（Preview Extension）
qlmanage -p path/to/test.zip

# Extensionの詳細確認
qlmanage -m | grep -i coverzip

# 両方のExtensionが登録されているかチェック
pluginkit -m | grep -i coverzip
```

## 技術的詳細

### 主要な設計パターン

#### 1. アプリケーション起動フロー
```
ZIPファイルドロップ → AppDelegate:application:open:urls: → 
processZipFile → KeywordMatcher → AppLauncher → NSApplication.terminate
```

#### 2. Extension設定

**Thumbnail Extension:**
- **NSExtensionPointIdentifier**: `com.apple.quicklook.thumbnail`
- **NSExtensionPrincipalClass**: `ThumbnailProvider`
- **サポートファイル形式**: ZIPファイル（`public.zip-archive`）

**Preview Extension:**
- **NSExtensionPointIdentifier**: `com.apple.quicklook.preview`
- **NSExtensionPrincipalClass**: `PreviewProvider` または `PreviewViewController`
- **サポートファイル形式**: ZIPファイル（`public.zip-archive`）
- **App Group**: `group.com.dmng.CoverZip`（設定共有用）

#### 3. Settings Scene アーキテクチャ
- WindowGroupの代替としてSettings sceneを使用
- 不要なウィンドウ生成を回避しバックグラウンド処理に最適化
- Cmd+,でアクセス可能な設定ファイル編集ボタン提供

### 実装のポイント
1. **責任分離**: 3つのコンポーネント（Thumbnail、Preview、App）の明確な分離
2. **純Swift実装**: 外部ライブラリに依存しない軽量設計
3. **メモリ最適化**: 8MBバッファによる制御されたメモリ使用
4. **即座終了**: 外部アプリ起動後の自動終了でリソース解放
5. **一時ファイル管理**: サンドボックス制約に対応した一時ファイル作成・削除
6. **App Group共有**: Preview ExtensionとMain Appで設定を共有
7. **UIレスポンシブ設計**: ウィンドウ幅に応じてUIコンポーネント表示を動的制御

## 開発時の注意点

### Extension の特徴
- QuickLook Extension（Thumbnail/Preview）は独立したプロセスで動作
- サンドボックス環境での制限
- メモリ使用量の制限（8MBバッファ）
- Preview ExtensionではNSViewController使用（フルUIコントロール）

### デバッグ方法
- Extension のデバッグには特別な設定が必要
- System Preferences > Extensions > QuickLookでの有効化が必要
- `qlmanage -r` でExtensionをリロード
- Preview Extension開発時は `qlmanage -p` でテスト

### ZIPファイル処理の技術詳細
- **純Swift実装**: Foundation/Compressionフレームワークのみ使用
- **対応圧縮方式**: DEFLATE（方式8）と非圧縮（方式0）
- **対応画像形式**: .jpg, .jpeg, .png, .gif, .bmp, .tiff, .ico, .icns
- **メモリ効率**: 8MBバッファによる制御されたメモリ使用
- **ファイル名エンコーディング**: UTF-8対応、__MACOSX隠しファイル除外

## システム要件

- **macOS**: 11.0 (Big Sur) 以降
- **アーキテクチャ**: Universal Binary (Intel x86_64 + Apple Silicon arm64)
- **開発環境**: Xcode 14.0 以降

## 実装制約

### 制限事項
- 暗号化ZIPファイルは未対応
- 大容量ZIPファイルでのメモリ制限
- DEFLATE以外の圧縮方式は未対応

### App Extension環境
- 独立プロセスでの動作（Thumbnail/Preview両方）
- サンドボックス制約下での実装
- QuickLook Thumbnail/Preview Extensionとしての二重登録必須
- App Group (`group.com.dmng.CoverZip`) による設定データ共有

## 設定ファイル（settings.json）

### 新しい設定形式
```json
{
  "keywords": {
    "コミック": {
      "type": "filename",
      "application": "SimpleComicViewer.app",
      "matchMode": "contains"
    },
    "manga": {
      "type": "filename",
      "application": "SimpleComicViewer.app",
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
- **contains**: 部分一致検索（デフォルト）
- **wildcard**: ワイルドカード (`*`, `?`) 対応
- **regex**: 正規表現対応

### キーワードタイプ
- **filename**: ZIPファイル名でマッチング（拡張子除く）
- **pathname**: ZIPファイルのフルパスでマッチング

### 設定管理
- **場所**: `~/Library/Application Support/CoverZip/settings.json`
- **編集**: Settings画面（Cmd+,）から外部エディタで編集
- **自動生成**: 初回起動時にデフォルト設定を自動作成

## App Group共有設定

Preview ExtensionとMain Appでは、App Group (`group.com.dmng.CoverZip`) を通じて以下の設定を共有：

### 共有設定項目
- **isRightToLeftReading**: 右から左読み設定（デフォルト: true）
- **sliderVisibilityWidthThreshold**: スライダー表示閾値（デフォルト: 600px）

### 設定クラス
- `AppSettings` (Main App) / `AppSettings` (Preview Extension) で同期
- `UserDefaults(suiteName: "group.com.dmng.CoverZip")` 使用