# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

CoverZipは、ZIPファイルのサムネイルを表示するmacOS QuickLook Extensionです。ZIPファイル内の先頭の画像ファイルを使用してサムネイルを生成し、Finderでの視覚的な識別を可能にします。

## アーキテクチャ

### コアコンポーネント分離設計
1. **ThumbnailProvider.swift** - QuickLook拡張機能のエントリーポイント
   - `QLThumbnailProvider`を継承したメインクラス
   - 画像の縦横比維持とスケーリング処理
   - `ZipProcessor`を呼び出してZIPファイル処理を委譲

2. **ZipProcessor.swift** - ZIP処理専用クラス（純Swift実装）
   - ZIPファイルの解析（Central Directory + Local File Header）
   - DEFLATE圧縮データの展開（8MBバッファ）
   - 画像ファイルの検出と抽出
   - 外部ライブラリ不要、標準フレームワークのみ使用

### App Extension制約への対応
- サンドボックス環境での動作保証
- メモリ使用量の最適化（8MBバッファ制限）
- App Extensionプロセス分離への適合

### プロジェクト構造
- `CoverZip/` - SwiftUIベースのメインアプリケーション（Document-based App）
- `coverZipExtension/` - QuickLook Thumbnail Extension
  - `ThumbnailProvider.swift` - QuickLookエントリーポイント
  - `ZipProcessor.swift` - ZIP処理ロジック
  - `Info.plist` - Extension設定
- `CoverZipTests/` - Swift Testingベースのユニットテスト
- `CoverZipUITests/` - UI自動化テスト
- `HetimaZip-qlgenerator-master/` - 旧実装（参考用）

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

### Extensionのテスト
```bash
# QuickLook Extensionをリロード
qlmanage -r

# 特定のZIPファイルでサムネイル生成テスト
qlmanage -t path/to/test.zip

# Extensionの詳細確認
qlmanage -m | grep -i coverzip
```

## 技術的詳細

### Extension の設定
- **NSExtensionPointIdentifier**: `com.apple.quicklook.thumbnail`
- **NSExtensionPrincipalClass**: `ThumbnailProvider`
- **サポートファイル形式**: ZIPファイル（`public.zip-archive`）

### 実装のポイント
1. **責任分離**: `ThumbnailProvider`（UI処理）と`ZipProcessor`（ファイル処理）の明確な分離
2. **純Swift実装**: 外部ライブラリに依存しない軽量設計
3. **メモリ最適化**: 8MBバッファによる制御されたメモリ使用
4. **エラーハンドリング**: NSErrorベースの段階的フォールバック

## 開発時の注意点

### Extension の特徴
- QuickLook Extensionは独立したプロセスで動作
- サンドボックス環境での制限
- メモリ使用量の制限（8MBバッファ）

### デバッグ方法
- Extension のデバッグには特別な設定が必要
- System Preferencesでの有効化が必要
- `qlmanage -r` でExtensionをリロード

### ZIPファイル処理の技術詳細
- **純Swift実装**: Foundation/Compressionフレームワークのみ使用
- **対応圧縮方式**: DEFLATE（方式8）と非圧縮（方式0）
- **対応画像形式**: .jpg, .jpeg, .png, .gif, .bmp, .tiff, .ico, .icns
- **メモリ効率**: 8MBバッファによる制御されたメモリ使用
- **ファイル名エンコーディング**: UTF-8対応、__MACOSX隠しファイル除外

## 実装制約

### 制限事項
- 暗号化ZIPファイルは未対応
- 大容量ZIPファイルでのメモリ制限
- DEFLATE以外の圧縮方式は未対応

### App Extension環境
- 独立プロセスでの動作
- サンドボックス制約下での実装
- QuickLook Thumbnail Extensionとしての登録必須