# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

CoverZipは、ZIPファイルのサムネイルを表示するmacOS QuickLook Extensionです。ZIPファイル内の先頭の画像ファイルを使用してアイコンを生成します。

## プロジェクト構造

### メインアプリケーション
- `CoverZip/` - メインアプリケーション（Document-based App）
- `CoverZipTests/` - ユニットテスト
- `CoverZipUITests/` - UIテスト

### QuickLook Extension
- `coverZipExtension/` - QuickLook Thumbnail Extension
  - `ThumbnailProvider.swift` - サムネイル生成のメインクラス
  - `Info.plist` - Extension設定

### リファレンスコード
- `HetimaZip-qlgenerator-master/` - 古いQuickLook Generatorの実装（参考用）
  - `GenerateThumbnailForURL.m` - サムネイル生成のエントリーポイント
  - `HZQZipItem.m` - ZIPファイルの処理
  - `HZQImageAgent.m` - 画像処理

## ビルドと開発

### ビルド方法
```bash
# Xcodeでプロジェクトを開く
open CoverZip.xcodeproj

# コマンドラインでビルド（コードサイン無効）
xcodebuild -project CoverZip.xcodeproj -scheme CoverZip build CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Extension単体のビルド
xcodebuild -project CoverZip.xcodeproj -target coverZipExtension build -configuration Debug CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

### Extension のテスト
```bash
# QuickLook Extension を確認
qlmanage -r
qlmanage -t path/to/test.zip
```

## 技術的詳細

### Extension の設定
- **NSExtensionPointIdentifier**: `com.apple.quicklook.thumbnail`
- **NSExtensionPrincipalClass**: `ThumbnailProvider`
- **サポートファイル形式**: ZIPファイル（設定が必要）

### 実装のポイント
1. `QLThumbnailProvider` を継承した `ThumbnailProvider` クラス
2. `provideThumbnail(for:_:)` メソッドでサムネイル生成
3. ZIPファイル内の画像ファイルを抽出してサムネイル化

### リファレンスコードの重要な機能
- `HZQZipItem`: ZIPファイルの解析とファイル一覧取得
- `imageDataArrayWithExpectation`: ZIP内の画像データを取得
- `anyImageData`: 先頭の画像データを取得
- minizipライブラリによるZIPファイル処理

## 開発時の注意点

### Extension の特徴
- QuickLook Extensionは独立したプロセスで動作
- サンドボックス環境での制限
- メモリ使用量の制限

### デバッグ方法
- Extension のデバッグには特別な設定が必要
- System Preferencesでの有効化が必要
- `qlmanage -r` でExtensionをリロード

### ZIPファイル処理
- C言語のminizipライブラリを使用
- ファイル名のエンコーディング処理（UTF-8, Shift-JIS）
- 画像ファイルの検出（.jpg, .png, .icns など）

## 実装内容

### 完了した機能
- **ZIPファイル解析**: 純SwiftでZIPファイルのCentral DirectoryとLocal File Headerを解析
- **画像ファイル検出**: .jpg, .jpeg, .png, .gif, .bmp, .tiff, .ico, .icns 形式の画像を検出
- **DEFLATE展開**: Compression frameworkを使用したZIPファイル内の圧縮データ展開
- **縦横比維持**: 画像の縦横比を保持したサムネイル生成
- **AppKit統合**: NSImageとNSBezierPathを使用した描画

### 実装の特徴
- **外部ライブラリ不要**: 標準のFoundationとCompressionフレームワークのみ使用
- **サンドボックス対応**: App Extensionの制限に準拠
- **軽量実装**: minizipライブラリを使用せず、純Swift実装

### 既知の制限事項
- **暗号化ZIP**: パスワード付きZIPファイルは未対応
- **圧縮方式**: DEFLATE（方式8）と非圧縮（方式0）のみ対応
- **ファイルサイズ**: 大きなZIPファイルでのメモリ制限

## 今後の改善予定
- エラーハンドリングの強化
- 圧縮方式の追加対応
- パフォーマンスの最適化