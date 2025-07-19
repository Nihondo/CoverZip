# CoverZip

CoverZipは、ZIPファイルのサムネイルを表示するmacOS QuickLook Extensionです。ZIPファイル内の先頭の画像ファイルを使用してアイコンを生成し、Finderでの視覚的な識別を可能にします。

## 特徴

- **ZIPファイルサムネイル生成**: ZIPファイル内の最初の画像ファイルを使用してサムネイルを生成
- **純Swift実装**: 標準のFoundationとCompressionフレームワークのみを使用
- **App Extension対応**: macOS QuickLook Thumbnail Extensionとして実装
- **軽量**: 外部ライブラリに依存しない軽量な実装

## 対応ファイル形式

### ZIPファイル
- 標準的なZIPファイル（.zip）
- DEFLATE圧縮（方式8）と非圧縮（方式0）に対応

### 画像ファイル
- JPEG (.jpg, .jpeg)
- PNG (.png)
- GIF (.gif)
- BMP (.bmp)
- TIFF (.tiff)
- ICO (.ico)
- ICNS (.icns)

## システム要件

- macOS 10.15 (Catalina) 以降
- Xcode 14.0 以降（開発時）

## インストール

### 開発者向け（ソースからビルド）

1. リポジトリをクローンまたはダウンロード
2. Xcodeでプロジェクトを開く
3. プロジェクトをビルドして実行

```bash
# プロジェクトを開く
open CoverZip.xcodeproj

# コマンドラインでビルド
xcodebuild -project CoverZip.xcodeproj -scheme CoverZip build
```

### Extension の有効化

1. アプリケーションを一度実行
2. システム設定 > プライバシーとセキュリティ > 機能拡張 > QuickLook
3. CoverZipを有効化

## 使用方法

1. インストール後、Finderでサムネイル表示を有効にします
2. ZIPファイルを含むフォルダで、表示 > サムネイル を選択
3. 画像を含むZIPファイルのサムネイルが自動的に生成されます

## 開発

### プロジェクト構造

```
CoverZip/
├── CoverZip/                  # メインアプリケーション
│   ├── CoverZipApp.swift      # アプリケーションエントリーポイント
│   ├── ContentView.swift      # メインビュー
│   └── CoverZipDocument.swift # Document-based App
├── coverZipExtension/         # QuickLook Extension
│   ├── ThumbnailProvider.swift # サムネイル生成メインクラス
│   └── Info.plist            # Extension設定
├── CoverZipTests/            # ユニットテスト
└── CoverZipUITests/          # UIテスト
```

### ビルドとテスト

```bash
# Extension単体のビルド
xcodebuild -project CoverZip.xcodeproj -target coverZipExtension build -configuration Debug

# QuickLook Extension のテスト
qlmanage -r                    # Extensionをリロード
qlmanage -t path/to/test.zip   # 特定のZIPファイルでテスト
```

### 技術的詳細

#### ZIP解析
- Central DirectoryとLocal File Headerの純Swift実装
- Foundation/Compressionフレームワークを使用したDEFLATE展開
- エンコーディング問題への対応

#### サムネイル生成
- NSImageとNSBezierPathを使用
- 画像の縦横比を保持したリサイズ
- App Extensionのメモリ制限に配慮した実装

## 制限事項

- **暗号化ZIP**: パスワード付きZIPファイルは未対応
- **圧縮方式**: DEFLATE（方式8）と非圧縮（方式0）のみ対応
- **大容量ファイル**: 大きなZIPファイルでのメモリ制限あり
