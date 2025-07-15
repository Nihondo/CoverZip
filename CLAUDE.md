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

# コマンドラインでビルド
xcodebuild -project CoverZip.xcodeproj -scheme CoverZip build
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

## 今後の実装予定
- ZIPファイル内の先頭画像からサムネイル生成
- 画像ファイル形式の判定と処理
- エラーハンドリングとフォールバック処理