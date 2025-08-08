# CoverZip

CoverZipは、二つの独立した機能を持つmacOSアプリケーションです：

1. **QuickLook Thumbnail Extension** - ZIPファイル内の先頭画像を使用したサムネイル生成
2. **ZIPファイルルーティングアプリケーション** - ファイル名キーワードマッチングによる外部アプリケーション自動起動

## 特徴

### QuickLook Extension
- **ZIPファイルサムネイル生成**: ZIPファイル内の最初の画像ファイルを使用してサムネイルを生成
- **純Swift実装**: 標準のFoundationとCompressionフレームワークのみを使用
- **App Extension対応**: macOS QuickLook Thumbnail Extensionとして実装
- **軽量**: 外部ライブラリに依存しない軽量な実装

### ファイルルーティング機能
- **キーワードマッチング**: ZIPファイル名に基づいた自動アプリケーション起動
- **JSON設定**: 柔軟なキーワード→アプリケーション マッピング設定
- **バックグラウンド動作**: 不要なウィンドウ生成なしでの処理
- **自動終了**: 外部アプリケーション起動後の即座終了

## 対応ファイル形式

### ZIPファイル
- 標準的なZIPファイル（.zip）
- DEFLATE圧縮（方式8）と非圧縮（方式0）に対応

### 画像ファイル（サムネイル生成用）
- JPEG (.jpg, .jpeg)
- PNG (.png)
- GIF (.gif)
- BMP (.bmp)
- TIFF (.tiff, .tif)
- ICO (.ico)
- ICNS (.icns)

## システム要件

- macOS 11.0 (Big Sur) 以降
- Intel Mac (x86_64) および Apple Silicon Mac (arm64) 対応
- Xcode 14.0 以降（開発時）

## インストール

### 開発者向け（ソースからビルド）

1. リポジトリをクローンまたはダウンロード
2. Xcodeでプロジェクトを開く
3. プロジェクトをビルドして実行

```bash
# プロジェクトを開く
open CoverZip.xcodeproj

# コマンドラインでビルド（コードサイン無効）
xcodebuild -project CoverZip.xcodeproj -scheme CoverZip build CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

### Extension の有効化

1. アプリケーションを一度実行
2. システム設定 > プライバシーとセキュリティ > 機能拡張 > QuickLook
3. CoverZipを有効化

## 使用方法

### QuickLook サムネイル機能
1. インストール後、Finderでサムネイル表示を有効にします
2. ZIPファイルを含むフォルダで、表示 > サムネイル を選択
3. 画像を含むZIPファイルのサムネイルが自動的に生成されます

### ZIPファイルルーティング機能
1. CoverZipにZIPファイルをドロップまたは関連付けで開く
2. ファイル名に基づいてキーワードマッチングが実行
3. 設定に応じて適切な外部アプリケーションが自動起動
4. CoverZipは自動的に終了

## 設定ファイル

ファイルルーティング機能は、JSON設定ファイルで制御されます。

### 設定ファイルの場所
```
~/Library/Application Support/CoverZip/settings.json
```

### 設定例

アプリケーション初回起動時に、以下の内容でデフォルトの設定ファイルが自動生成されます。このファイルは後から自由に編集できます。

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
    "comic": {
      "type": "pathname",
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
    },
    "写真": {
      "type": "filename",
      "application": "Photos.app",
      "matchMode": "contains"
    },
    "photo": {
      "type": "pathname",
      "application": "Photos.app",
      "matchMode": "contains"
    }
  },
  "default": "Archive Utility.app"
}
```

#### マッチング方式の説明
- **contains** (デフォルト): 部分一致検索
  - 例: `"comic"` → `comic_vol1.zip` にマッチ
- **wildcard**: ワイルドカード (`*`, `?`) 対応
  - 例: `"vol*"` → `vol1.zip`, `vol_special.zip` にマッチ
  - 例: `"*backup*"` → `auto_backup_2024.zip` にマッチ
- **regex**: 正規表現対応
  - 例: `"^backup_\\d+$"` → `backup_123` にマッチ（先頭末尾固定）
  - 例: `"(manga|comic)"` → `manga.zip`, `comic.zip` にマッチ

#### キーワードタイプの説明
- **filename**: ZIPファイル名でマッチング（拡張子除く）
- **pathname**: ZIPファイルのフルパスでマッチング

### 設定の編集
1. Cmd+, または アプリメニューから CoverZip > Settings... を選択
2. 設定画面で「設定ファイルを編集」ボタンをクリック
3. 外部エディタで settings.json を編集
4. 変更は次回のファイル処理時に自動反映

## 開発

### プロジェクト構造

```
CoverZip/
├── CoverZip/                    # メインアプリケーション
│   ├── CoverZipApp.swift        # SwiftUI Appライフサイクルエントリーポイント
│   ├── AppDelegate.swift        # ファイル処理、アプリケーションデリゲート
│   ├── Services/                # ビジネスロジック層
│   │   ├── KeywordMatcher.swift    # ファイル名マッチング
│   │   ├── AppLauncher.swift       # 外部アプリ起動
│   │   └── SettingsFileManager.swift # 設定ファイル管理
│   └── Models/
│       └── KeywordSettings.swift   # JSON設定データモデル
├── coverZipExtension/           # QuickLook Thumbnail Extension
│   ├── ThumbnailProvider.swift  # QuickLookエントリーポイント
│   ├── ZipProcessor.swift       # ZIP処理ロジック（純Swift実装）
│   └── Info.plist              # Extension設定
├── CoverZipTests/              # Swift Testingベースのユニットテスト
└── CoverZipUITests/            # UI自動化テスト
```

### ビルドとテスト

```bash
# Extension単体のビルド
xcodebuild -project CoverZip.xcodeproj -target coverZipExtension build -configuration Debug CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# QuickLook Extension のテスト
qlmanage -r                    # Extensionをリロード
qlmanage -t path/to/test.zip   # 特定のZIPファイルでテスト
qlmanage -m | grep -i coverzip # Extension登録状況確認
```

### 技術的詳細

#### アプリケーション起動フロー
```
ZIPファイルドロップ → AppDelegate:application:open:urls: → 
processZipFile → KeywordMatcher → AppLauncher → NSApplication.terminate
```

#### ZIP解析（Extension側）
- Central DirectoryとLocal File Headerの純Swift実装
- Foundation/Compressionフレームワークを使用したDEFLATE展開
- 8MBメモリバッファによる制御されたメモリ使用
- エンコーディング問題への対応

#### サムネイル生成
- NSImageとNSBezierPathを使用
- 画像の縦横比を保持したリサイズ
- App Extensionのメモリ制限に配慮した実装

#### Settings Scene アーキテクチャ
- WindowGroupの代替としてSettings sceneを使用
- 不要なウィンドウ生成を回避しバックグラウンド処理に最適化
- Cmd+,でアクセス可能な設定ファイル編集機能

## アーキテクチャの特徴

### 責任分離
- **Extension**: サムネイル生成のみに専念
- **App**: ファイルルーティングのみに専念
- **共通**: ZipProcessor（純Swift ZIP処理ロジック）

### パフォーマンス最適化
- 一時ファイル作成を廃止し、元ファイルを直接使用
- メモリ効率的な8MBバッファ制限
- 外部アプリ起動後の即座終了でリソース解放

### 設定管理
- JSON設定ファイルによる柔軟なキーワードマッピング
- 外部エディタでの設定編集機能
- 初回起動時のデフォルト設定自動生成

## 制限事項

- **暗号化ZIP**: パスワード付きZIPファイルは未対応
- **圧縮方式**: DEFLATE（方式8）と非圧縮（方式0）のみ対応
- **大容量ファイル**: 大きなZIPファイルでのメモリ制限あり（8MBバッファ）

## ライセンス

このプロジェクトは開発目的で作成されています。