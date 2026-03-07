# CoverZip

CoverZipは、四つの独立した機能を持つmacOSアプリケーションです：

1. **QuickLook Thumbnail Extension** - ZIPファイル内の先頭画像を使用したサムネイル生成
2. **QuickLook Preview Extension** - ZIPファイル内画像のフルスクリーンプレビューとページング機能
3. **ZIPファイルルーティングアプリケーション** - ファイル名キーワードマッチングによる外部アプリケーション自動起動
4. **内蔵ビューア** - アプリ内でQLPreviewViewを使用したZIP画像表示機能

## 特徴

### QuickLook Thumbnail Extension
- **ZIPファイルサムネイル生成**: ZIPファイル内の最初の画像ファイルを使用してサムネイルを生成
- **純Swift実装**: 標準のFoundationとCompressionフレームワークのみを使用
- **App Extension対応**: macOS QuickLook Thumbnail Extensionとして実装
- **軽量**: 外部ライブラリに依存しない軽量な実装
- **先頭画像の早期判定(オプション)**: 表紙らしい名前（`cover`/`front`/`表紙`/`00*`）を優先し、次いで0埋め1（`01`/`001`/`image001` など）を採用。したがって連番が混在する場合は `000` 系を `001` より優先して表紙と判断。`CZZip.firstImageData(from:options:)` を利用（例: `[.preferCoverLike, .preferZeroPaddedOne]`）。

### QuickLook Preview Extension
- **フルスクリーンプレビュー**: ZIPファイル内のすべての画像をフルスクリーンで表示
- **ページング機能**: マウスクリック・キーボードでのページ移動
- **遅延ロード方式**: メタデータを先行取得し、画像データは必要時にロード
  - 2ページ目以降への高速遷移（全画像読み込み待ちなし）
  - メモリ効率的なキャッシュ管理（元画像10枚、リサイズ画像20枚）
  - 隣接ページの自動プリロード
- **表示モード**: 単ページ/見開き/自動（画像サイズに応じた判定）
- **ページスライダー**: ページ位置を視覚的に表示・操作
- **RTL読書対応**: 日本のコミック向け右から左への読書方向
- **履歴機能**: ZIP別に最終閲覧ページと表示設定を記憶
- **レスポンシブUI**: ウィンドウ幅に応じてUI要素を動的調整
- **設定共有**: App Groupによるメインアプリとの設定同期
- **ページ送りアニメ設定**: 設定画面からON/OFF可能（既定値を共有）
- **サムネイルリスト初期表示設定**: 設定画面からON/OFF可能（右クリックメニューでも切り替え可能）
- **サムネイル並び方向**: 右綴じは右→左（少ページ時も右端基準）、左綴じは左→右で表示
- **見開き時のサムネイル選択**: 表示中の2ページを同時に選択表示

### 内蔵ビューア機能
- **QLPreviewView統合**: QuickLook Preview Extensionと同じプレビュー体験
- **キーボードナビゲーション**: 左右矢印キーでのページ送り（合成クリック方式）
- **コンテキストメニュー**: 右クリックで読書方向/表示モード/見開き補正/サムネイルリスト表示/ページ送りアニメ/スライドショーを切り替え（QuickLookビューアと同一構成）
- **複数ウィンドウ対応**: 複数のZIPファイルを同時に表示可能
- **"internal"キーワード**: 設定ファイルで内蔵ビューアを指定可能
- **Cmd+O対応**: メニューまたはキーボードショートカットで直接開く

### ファイルルーティング機能
- **キーワードマッチング**: ZIPファイル名に基づいた自動アプリケーション起動
- **JSON設定**: 柔軟なキーワード→アプリケーション マッピング設定
- **バックグラウンド動作**: 不要なウィンドウ生成なしでの処理
- **自動終了**: 外部アプリケーション起動後の即座終了（内蔵ビューア使用時は継続）

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
3. CoverZip（両方のExtension）を有効化
   - CoverZip Thumbnail Extension
   - CoverZip Preview Extension

## 使用方法

### QuickLook サムネイル機能
1. インストール後、Finderでサムネイル表示を有効にします
2. ZIPファイルを含むフォルダで、表示 > サムネイル を選択
3. 画像を含むZIPファイルのサムネイルが自動的に生成されます

### QuickLook プレビュー機能
1. Finderで画像を含むZIPファイルを選択
2. スペースキーを押すかプレビューアイコンをクリック
3. フルスクリーンでZIPファイル内の画像が表示されます

#### プレビュー操作方法
- **ページ移動**: 画面の左右をクリック、または矢印キーで移動
- **マウスホイール**: 上下スクロールでページ送り/戻し（読書方向設定に対応）
- **スライダー操作**: ページスライダーをクリック・ドラッグで任意のページへジャンプ
- **キーボード操作**:
  - 左右矢印キー: ページ移動（読書方向設定に応じて動作）
  - Home/End: 最初/最後のページへ
  - Page Up/Down: 5ページずつ移動
  - Escape: プレビューを閉じる

### アプリ内プレビュー（内蔵ビューア）
- アプリ内でも Quick Look のプレビューを使用しています（`QLPreviewView` 埋め込み）。
- キー入力は専用のフォワーダビューで受け取り、プレビュー領域左右へのクリックを合成してページ移動します。
- 安定性のため、ウィンドウを閉じる際は OS の標準解放順序に任せ、独自のビュー破棄は行いません（2025-09 変更）。

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
│   │   ├── SettingsFileManager.swift # 設定ファイル管理
│   │   └── AppSettings.swift       # App Group共有設定
│   └── Models/
│       └── KeywordSettings.swift   # JSON設定データモデル
├── coverZipExtension/           # QuickLook Thumbnail Extension
│   ├── ThumbnailProvider.swift  # サムネイル生成エントリーポイント
│   ├── ZipProcessor.swift       # ZIP処理ロジック（純Swift実装）
│   └── Info.plist              # Extension設定
├── coverZipViewer/             # QuickLook Preview Extension
│   ├── PreviewProvider.swift   # プレビューエントリーポイント
│   ├── PreviewViewController.swift # プレビューUI制御（NSViewController）
│   ├── ImageManager.swift      # 画像管理・ページング制御（遅延ロード実装）
│   ├── ReadingHistoryManager.swift # 閲覧履歴管理
│   ├── Settings.swift          # App Group共有設定
│   ├── Base.lproj/
│   │   └── PreviewViewController.xib # UI定義
│   └── Info.plist              # Extension設定
├── Shared/                     # 共有ユーティリティ
│   ├── ZipCore.swift           # 純Swift ZIP処理コア
│   ├── NaturalSort.swift       # 自然順ソート
│   ├── ImageFileFilter.swift   # 画像ファイル判定
│   ├── SettingsKeys.swift      # 共有設定キー
│   └── ImageIOOptions.swift    # 画像生成オプション
├── CoverZipTests/              # Swift Testingベースのユニットテスト
└── CoverZipUITests/            # UI自動化テスト
```

### ビルドとテスト

```bash
# Extension単体のビルド
xcodebuild -project CoverZip.xcodeproj -target coverZipExtension build -configuration Debug CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
xcodebuild -project CoverZip.xcodeproj -target coverZipViewer build -configuration Debug CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# QuickLook Extension のテスト
qlmanage -r                    # Extensionをリロード
qlmanage -t path/to/test.zip   # サムネイル生成テスト
qlmanage -p path/to/test.zip   # プレビューテスト
qlmanage -m | grep -i coverzip # Extension登録状況確認
pluginkit -m | grep -i coverzip # 詳細なExtension情報
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

#### Preview Extension UI
- NSViewControllerベースのフルUI制御
- ページスライダー・ページ番号表示
- マウス/キーボード/スクロールホイール操作対応
- RTL読書方向（右から左）対応
- レスポンシブUIデザイン

#### 遅延ロード実装
- **メタデータ先行取得**: `CZZip.imageEntryInfoList()`でファイル名とエントリ情報のみを高速取得
- **オンデマンドロード**: `CZZip.extractImageData()`で表示時に画像データを抽出
- **2段階キャッシュ**: 元画像キャッシュ（10枚）とリサイズキャッシュ（20枚）
- **プリロード戦略**: 隣接ページをバックグラウンドで自動プリロード
- **自然順ソート**: `NaturalSort.lessFilename()`による数値認識ソート（01.jpg < 02.jpg < 10.jpg）

#### Settings Scene アーキテクチャ
- WindowGroupの代替としてSettings sceneを使用
- 不要なウィンドウ生成を回避しバックグラウンド処理に最適化
- Cmd+,でアクセス可能な設定ファイル編集機能

## アーキテクチャの特徴

### 責任分離
- **Thumbnail Extension**: サムネイル生成のみに専念
- **Preview Extension**: フルスクリーンプレビュー・ページング機能（遅延ロード実装）
- **Main App**: ファイルルーティングと内蔵ビューア機能
- **共通**: ZipCore（純Swift ZIP処理ロジック）、NaturalSort、設定管理（App Group）

### パフォーマンス最適化
- **遅延ロード方式**: メタデータ先行取得により2ページ目以降への即座遷移を実現
- **メモリ効率**: 必要な画像のみをロード、2段階キャッシュ管理
- **プリロード戦略**: 隣接ページをバックグラウンドで先読み
- **リサイズ最適化**: 表示サイズに最適化された画像をキャッシュ
- 一時ファイル作成を廃止し、元ファイルを直接使用
- ZIP解析時の8MBバッファ制限
- 外部アプリ起動後の即座終了でリソース解放

### 設定管理
- JSON設定ファイルによる柔軟なキーワードマッピング
- 外部エディタでの設定編集機能
- 初回起動時のデフォルト設定自動生成
- App Group (`group.com.dmng.CoverZip`) による Extension との設定共有

## 制限事項

- **暗号化ZIP**: パスワード付きZIPファイルは未対応
- **圧縮方式**: DEFLATE（方式8）と非圧縮（方式0）のみ対応
- **大容量ファイル**: 大きなZIPファイルでのメモリ制限あり（8MBバッファ）
- **Preview Extension**: サンドボックス環境での制約、独立プロセスでの実行

## ライセンス

このプロジェクトは開発目的で作成されています。
