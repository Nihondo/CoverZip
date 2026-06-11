# CoverZip 高速化プラン（第2弾）

これまでの最適化（遅延ロード、ダウンサンプルデコード、プリレンダーレイヤーキャッシュ、
ストリーミングサムネイル生成等）を踏まえ、コードベース調査で特定した残りの高速化ポイントを
優先度別にまとめた実装計画。**実装エージェントはこのドキュメントの単位（A-1, A-2, ...）ごとに
独立したコミットを作ること。**

## 対象となるホットパス

| 経路 | 入口 | 通過するコード |
|------|------|----------------|
| Finder サムネイル生成 | `ThumbnailProvider.provideThumbnail` | `CZZip.firstImageThumbnail` → CDパース → 表紙選定 → 展開 → ImageIO |
| プレビューを開く | `PreviewViewController.preparePreviewOfFile` | `ImageManager.loadImages` → `CZZip.imageEntryInfoList`（CDパース + 全件ソート）→ 先頭ページ展開・デコード |
| ページ送り | `performPageNavigation` | `ImageManager.getImageAtIndex`（展開 + デコード）→ プリレンダー → 履歴保存 |
| サムネイルストリップ | `ThumbnailStripView.loadThumbnail` | セルごとに `CZZip.extractImageData` + ImageIO |

---

## 優先度A: 効果大・体感に直結

### A-1. ZIPパースのバイトアクセスを `subdata` から直接ポインタ読みに変更

**対象**: `Shared/ZipCore.swift`

**現状の問題**:
2〜4バイトの読み取りごとに `data.subdata(in:)` がヒープ確保を伴う `Data` コピーを生成している。

- `findCentralDirectoryOffset()`（ZipCore.swift:261 付近）: EOCDR 署名を末尾から1バイトずつ
  後方走査するループ内で、位置ごとに4バイトの `subdata` を確保。最大 65,536 回の `Data` 確保。
- `parseCentralDirectory()`（ZipCore.swift:281 付近）: エントリごとに約8回の `subdata`
  （gpFlag / compMethod / compressedSize / fnLen / exLen / cmLen / filename / localHeaderOffset）。
  1,000 エントリの ZIP で 8,000 回以上。
- `localFileInfo()` / `extractFileData()` のヘッダ読み（各5回程度）も同様。

**修正内容**:
1. `Data` 全体を一度だけ `withUnsafeBytes { (buf: UnsafeRawBufferPointer) in ... }` で包む
   ヘルパーを導入し、ヘッダフィールドは `buf.loadUnaligned(fromByteOffset:as: UInt16.self)` /
   `UInt32.self` で読む（macOS 11 ターゲットのため Swift の `loadUnaligned` が使えない場合は、
   バイト単位で組み立てる `readLE16/readLE32` ヘルパーを実装する。ZIPはリトルエンディアン固定）。
2. EOCDR 探索は `buf` 上のバイト比較ループに変更（`subdata` 廃止）。
3. 署名比較（`PK\x01\x02` 等）も `subdata(...).elementsEqual` をやめ、バイト直接比較にする。
4. ファイル名の `String` 化のみ `Data` 生成が必要（`String(decoding:as: UTF8.self)` を使い、
   失敗時フォールバックは現状維持）。

**注意点**:
- `Data` がスライス（`startIndex != 0`）の場合に備え、オフセット計算は `withUnsafeBytes` の
  バッファ基準（0始まり）で統一すること。現行コードは絶対インデックス前提なので、
  `imageEntries(from:)` 等の公開APIの入口で扱いを揃える。
- 範囲チェック（`offset + n <= buf.count`）は現行同様にすべての読みで行う。

**期待効果**: サムネイル生成・プレビューオープン・ページ抽出の全経路で、ZIPパース部分の
アロケーション数がほぼゼロになる。エントリ数の多いZIPほど効く。

**検証**: 既存の動作確認（`qlmanage -t/-p`）+ Instruments Allocations で
パース中の一時 `Data` 確保数を前後比較。

---

### A-2. DEFLATE展開を一発展開（`compression_decode_buffer`）に変更

**対象**: `Shared/ZipCore.swift`

**現状の問題**:
- Central Directory の **uncompressedSize（CDレコード内オフセット 24..28）をパースしていない**。
- そのため `inflateData()`（ZipCore.swift:337 付近）は出力サイズ不明のまま
  「64KB チャンクで `compression_stream_process` → `CFDataAppendBytes`」のループで伸長しており、
  出力バッファの再確保とコピーが繰り返される。
- `extractFileData()`（ZipCore.swift:315 付近）は圧縮ペイロードを `data.subdata(in:)` で
  **全量コピー**してから展開している（mmap された Data の利点を一部打ち消している）。

**修正内容**:
1. `CZZipEntry` に `uncompressedSize: Int` を追加し、`parseCentralDirectory` で
   CD レコードのオフセット 24..28 から読む。
2. `inflateData` を置き換える一発展開関数を追加:
   ```swift
   // dst を uncompressedSize ぴったりで確保し、
   // compression_decode_buffer(dst, dstSize, src, srcSize, nil, COMPRESSION_ZLIB)
   // 戻り値 == uncompressedSize を検証。0 や不一致なら従来のストリーミング実装へフォールバック。
   ```
   - `uncompressedSize == 0`（data descriptor 使用 ZIP で CD にも値がないケースは稀だが）
     のときは従来のストリーミング実装を使う。**既存の `inflateData` はフォールバックとして残す。**
3. `extractFileData` / `createThumbnail` の圧縮ペイロード取得を `subdata` から
   `withUnsafeBytes` 内のポインタ + オフセット渡しに変更し、コピーを1回削減する。
   非圧縮（method 0）の場合のみ最終的な `Data` コピーが必要（戻り値が ZIP 全体の
   mmap を保持し続けないようにするため。`Data(bytes:count:)` でコピーして返す現状方針を維持）。

**期待効果**: ページ送り・プリロード・サムネイルストリップで毎回走る展開処理の
CPU時間とメモリコピーが減る。特に大きな画像（数MB/ページ）で効く。

**検証**: 方式0（非圧縮）/方式8（DEFLATE）/data descriptor 付き ZIP それぞれで
画像が正しく表示されること。`[ImageManager][Decode]` ログの time 値を前後比較。

---

### A-3. 正規表現コンパイルの静的キャッシュ化

**対象**: `Shared/ZipCore.swift`

**現状の問題**:
- `isZeroPaddedOneFilename()`（ZipCore.swift:418 付近）: 呼び出しごとに
  `NSRegularExpression(pattern: "(?:^|\\D)0+1(?:\\D|$)")` を生成。
- `coverLikeScore()`（ZipCore.swift:466 付近）: 同じく毎回
  `NSRegularExpression(pattern: "(?:^|\\D)0{2,}(?:\\D|$)")` を生成し、さらに
  `isZeroPaddedOneFilename` も呼ぶ。
- `bestCoverLikeEntry()` は全画像エントリに対して `coverLikeScore` を呼ぶため、
  1,000 エントリの ZIP ではサムネイル生成1回あたり **2,000 回以上の正規表現コンパイル**が走る。

**修正内容**:
```swift
private static let zeroPaddedOneRegex = try? NSRegularExpression(pattern: "(?:^|\\D)0+1(?:\\D|$)")
private static let leadingZerosRegex  = try? NSRegularExpression(pattern: "(?:^|\\D)0{2,}(?:\\D|$)")
```
を導入し、各関数では `guard let re = Self.xxxRegex else { 既存フォールバック }` の形に変更。
`do/catch` は不要になる。

**期待効果**: Finder でフォルダを開いた際の一括サムネイル生成が大幅に短縮
（エントリ数に比例していたコンパイルコストが消える）。最小工数・最小リスクなので**最初に着手**。

---

### A-4. 自然順ソートのキー事前計算（Schwartzian transform）

**対象**: `Shared/NaturalSort.swift`, `Shared/ZipCore.swift`

**現状の問題**:
`NaturalSort.lessFilename()` は比較のたびに両辺の `lowercased()` + `tokenize()` を実行する
（NaturalSort.swift:17）。ソートは O(n log n) 回比較するため、1,000 エントリで約2万回の
トークン化が走る。また呼び出し側（`imageEntries` / `imageEntryInfoList` / 線形最小値探索）は
比較のたびに `(filename as NSString).lastPathComponent` を再計算している。

**修正内容**:
1. `NaturalSort` に事前計算キー API を追加:
   ```swift
   public struct NaturalSortKey: Comparable {
       // tokenize(lowercased()) の結果 + 元文字列（最終タイブレーク用）
       public init(_ s: String)
       public static func < (lhs: Self, rhs: Self) -> Bool  // 既存 naturalLess と同じ比較規則
   }
   ```
   既存の `lessFilename(_:_:)` は `NaturalSortKey(a) < NaturalSortKey(b)` の薄いラッパーとして
   残す（外部呼び出し互換のため）。
   - 注意: 既存の最終タイブレークは `localizedCompare`。キー化しても同じ結果になるよう
     元文字列をキーに保持して最後に `localizedCompare` する。
2. `CZZip.imageEntries` / `imageEntryInfoList` のソートを
   「`map { ($0, NaturalSortKey(lastPathComponent)) }` → キーで `sorted` → `map { $0.0 }`」に変更。
3. `firstImageEntryByNaturalOrderLinear` も best のキーを保持して比較する形に変更
   （現在は反復ごとに best 側も再トークン化している）。

**期待効果**: プレビューを開く際の `imageEntryInfoList`（毎回全件ソート）が
エントリ数の多いZIPで大幅短縮。ソート順は完全に同一であること。

**検証**: 数値混在・大文字小文字混在・日本語ファイル名のZIPで、修正前後のページ順が
一致すること（順序のスナップショット比較を行う）。

---

### A-5. 初回表示の二重デコード解消

**対象**: `coverZipViewer/ImageManager.swift`, `coverZipViewer/PreviewViewController.swift`

**現状の問題**:
`loadImages(from:)`（ImageManager.swift:143）は表示サイズ確定前に先頭ページを同期デコードする。
このとき `targetDisplaySizeInPoints == .zero` なのでフォールバックの 2048px バケットが使われる。
その後 `viewDidAppear` / リサイズで `setTargetDisplaySize` が呼ばれるとバケット署名が変わり、
`resizedImageCache` と `prerenderedLayerCache` を**全クリア**するため、先頭ページと
プリロード済みページが全て再デコードされる（＝オープン時に2回デコードしている）。

**修正内容**（2段構え）:
1. **サイズの先渡し**: `PreviewViewController.preparePreviewOfFile` で
   `imageManager.loadImages(from:)` を呼ぶ**前**に、利用可能なら
   `view.bounds.size` / `view.window` から `updateImageManagerDisplaySize()` を呼んで
   バケットを確定させる（`preparePreviewOfFile` 時点で view はロード済み。
   window が nil の場合は `NSScreen.main` のサイズを上限とした推定値を使う）。
2. **キャッシュクリアの緩和**: `setTargetDisplaySize` のバケット変更時、
   全クリアではなく「新バケットの `maxPixelSize` 以上でデコード済みのエントリは残す」
   方針にする。キャッシュキーにバケット寸法が入っているため、
   `resizedImageIndexMap` と同様に `key → maxPixelSize` を保持して判定する。
   プリレンダーレイヤーはキーが完全一致でしか参照されないためクリア継続でよいが、
   画像キャッシュが残れば再デコードなしでレイヤー再生成できる。

**期待効果**: ZIPを開いてから初回表示までの時間短縮（最大でデコード1回分）、
オープン直後のページ送りでのプリロードやり直しがなくなる。

**検証**: A群完了後に追加する signpost（後述）で
「`preparePreviewOfFile` 開始 → 初回 `displayCurrentImage` 完了」を前後比較。
`[ImageManager][Decode]` ログで同一ページの二重デコードが消えていることを確認。

---

## 優先度B: 体感に効くが影響範囲が局所的

### B-1. プリレンダーレイヤー生成の `DispatchQueue.main.sync` 排除

**対象**: `coverZipViewer/ImageManager.swift`

**現状の問題**:
`createPrerenderedLayer(from:)`（ImageManager.swift:711）がバックグラウンドの
`decodeQueue` / `layerBuildQueue` から `DispatchQueue.main.sync` を実行し、
メインスレッド上で `CALayer` 生成 + `setNeedsDisplay()` + `displayIfNeeded()` を行っている。

- プリロードは1ナビゲーションあたり最大6〜8レイヤーを作るため、メインスレッドが
  ページ送りアニメーション中に細切れにブロックされる。
- バックグラウンドスレッドがメインスレッド待ちで占有される（QoS 逆転の温床）。

**修正内容**:
- `CALayer` の生成・`contents` 設定・プロパティ設定は、レイヤーツリーに未アタッチであれば
  バックグラウンドスレッドで安全に行える。`main.sync` を外し、その場で生成して返す。
- `layer.setNeedsDisplay()` / `displayIfNeeded()` は `contents` を直接設定するレイヤーには
  不要なので削除する（`contents` 設定だけで GPU アップロード対象になる）。
- `targetDisplayScale` の読み取りがメインスレッド前提なら、デコード開始時点の値を
  キャプチャして渡す。

**注意点**: レイヤーを `hostLayer.addSublayer` するのは引き続きメインスレッド
（`PreviewViewController.setPrerenderedLayer`）。ここは変更しない。

**期待効果**: ページ送り連打時のメインスレッドのブロッキング解消、
プリレンダー完了までの時間短縮。

---

### B-2. 読書履歴保存のデバウンス

**対象**: `coverZipViewer/ReadingHistoryManager.swift`, `coverZipViewer/PreviewViewController.swift`

**現状の問題**:
`saveReadingPositionToHistory()` がページ送り・クリック・スライダー操作のたびに呼ばれ、
そのたびに `ReadingHistoryManager.saveReadingPosition` が
「履歴100件のJSONデコード → 配列再構築 → JSONエンコード → UserDefaults 書き込み」を
メインスレッドで実行する（ReadingHistoryManager.swift:43-73）。

**修正内容**:
1. `ReadingHistoryManager` に履歴配列のメモリキャッシュを持たせる
   （初回 `loadAllHistories` の結果を保持し、以後はメモリ上で更新）。
   外部プロセスとの同時書き込みは実運用上ない（書くのは Extension と内蔵ビューアだが
   同時に同じZIPを読むケースは無視できる）ため、ラスト・ライター・ウィンズで良い。
2. 永続化（JSONエンコード + `defaults.set`）は 0.5 秒のデバウンスタイマーで遅延実行。
3. `PreviewViewController.viewWillDisappear` と `deinit` 相当のタイミングで
   `flush()`（即時書き込み）を呼ぶ。`saveReadingPositionToHistory` の呼び出し箇所は変更不要。
4. ログ（`NSLog("[ReadingHistory] Saved...")`）はデバウンス後の実書き込み時のみ出す。

**期待効果**: ページ送り1回あたり数百KB規模のJSON往復が消え、連打時のカクつきが減る。

**検証**: ページ送り後にプレビューを閉じ、再オープンで最終ページが復元されること。
連打中に強制終了した場合に最大0.5秒分の位置が失われるのは許容仕様とする。

---

### B-3. プリロードの重複排除と方向最適化

**対象**: `coverZipViewer/ImageManager.swift`, `coverZipViewer/PreviewViewController.swift`

**現状の問題**:
1. **二重スケジュール**: `nextImage()` / `previousImage()`（ImageManager.swift:870, 890）が
   `preloadAdjacentImages(isSpreadMode: false)` を呼び、その直後に
   `displayCurrentImage` → `displaySingleImage` / `displaySpreadImages` が
   もう一度 `preloadAdjacentImages` を呼ぶ。1ナビゲーションで2回走る。
2. **モード不一致**: `nextImage` / `previousImage` は見開き表示中でも常に
   `isSpreadMode: false` でプリロードするため、見開き時に単ページ用レイヤーまで先読みして
   キャッシュ（max 10枚）を圧迫する。
3. **生デコードの in-flight 重複**: プリレンダーには `inFlightSinglePrerenderKeys` 等の
   重複排除があるが、`getImageAtIndex` の「展開 + デコード」自体にはない。
   プリロード（decodeQueue, concurrent）・`requestImageAsync`・プリレンダーが
   同じページを同時にデコードし得る。

**修正内容**:
1. `nextImage` / `previousImage` / `goToPage` 内の `preloadAdjacentImages` 呼び出しを削除し、
   表示側（`displaySingleImage` / `displaySpreadImages`）からの1回に統一する。
2. `getImageAtIndex` に `(cacheKey)` 単位の in-flight 集合 + 完了待ち合わせを追加:
   - シンプルな実装: `cacheStateQueue` 上で `inFlightDecodeKeys: Set<String>` を管理し、
     既に同キーのデコードが走っていればプリロード起源の呼び出しはスキップする
     （表示起源の同期呼び出しはそのまま実行して良い。最悪の重複は2回までに抑えられる）。
   - 完全な待ち合わせ（セマフォ/continuation）はデッドロックリスクがあるため行わない。
3. 余裕があれば: プリロードのインデックス列を読み方向（forward/backward の直近操作）に
   応じて前方優先で並べる（現状 `Set` 化で順序が壊れている点も直す。
   `Array(Set(...))` は順序不定なので、順序を保った重複排除に変更）。

**期待効果**: ナビゲーション1回あたりのバックグラウンド作業量がほぼ半減。
キャッシュ汚染（不要な単ページレイヤー）が消え、見開き連続ページ送りのヒット率が上がる。

---

### B-4. サムネイルストリップのデコード制御

**対象**: `coverZipViewer/ThumbnailStripView.swift`

**現状の問題**:
1. `loadThumbnail(at:)`（ThumbnailStripView.swift:356）は concurrent な `decodeQueue` に
   投げっぱなしで、高速スクロール時に画面外セルのデコードがキャンセルされない。
2. `reloadThumbnails()`（リサイズハンドル操作確定時）は `thumbnailCache` を全破棄して
   全件再デコードする。
3. `thumbnailCache: [Int: NSImage]` は件数無制限（1,000ページならNSImage 1,000枚）。
4. ImageManager と同じエントリをそれぞれ独立に展開している（圧縮データの inflate が二重）。

**修正内容**:
1. **世代トークン + 可視判定**: `configure` / `reloadThumbnails` でインクリメントする
   `generation: Int` を導入し、デコード完了時に世代が変わっていたら結果を捨てる。
   さらにデコード開始直前（バックグラウンド側）で
   「該当 indexPath が可視範囲±バッファ内か」をメインスレッドのスナップショット
   （`collectionView.visibleItems()` 由来の範囲を都度プロパティに保持）で判定し、
   範囲外ならスキップする。
2. **リサイズ時の即時表示**: `reloadThumbnails` でキャッシュを破棄せず、
   旧サイズのサムネイルをそのまま表示しつつ、新サイズのデコード完了後に差し替える。
   キャッシュキーを `Int`（index）から `index + サイズバケット` に拡張するか、
   「現在のターゲット高さと一致しないエントリは再デコード対象」とマークする方式にする。
3. **キャッシュ上限**: LRU で最大 200 件程度に制限（`NSCache` でも可。
   その場合 `countLimit` を設定）。
4. （任意・効果中）ImageManager 側に「展開済み元データの小さなLRU
   （index → Data、5〜10件）」を持たせ、ストリップとページデコードで共有する。
   実装コストが見合わなければ見送り可。

**期待効果**: 大量ページのZIPでストリップを高速スクロールした際の無駄なデコードが消え、
リサイズ時の白抜け時間が短くなる。

---

## 優先度C: 仕上げ・クリーンアップ

### C-1. ホットパスのログ削減

**対象**: `coverZipViewer/PreviewViewController.swift`, `coverZipViewer/ImageManager.swift`

- `setupMouseMonitors` 内のモニタクロージャは **マウスイベントごと**に複数の `NSLog` を
  実行している（座標・bounds の文字列化を含む）。`#if DEBUG` または
  `static let isVerboseLoggingEnabled`（環境変数 `CZ_VERBOSE_LOG` で有効化）でゲートする。
- `ImageManager.logDecodeResult` は**毎デコード**で `CGImageSourceCopyPropertiesAtIndex`
  （ソース画像のメタデータ再パース）+ NSLog を実行している。同様にゲートし、
  無効時は properties の取得自体をスキップする。
- `displayCurrentImage` 周辺・`preloadAdjacentImages` の `NSLog` も同様。
- os_signpost は残す（Releaseでも軽量）。

### C-2. `decodeCachePolicy` のスナップショット化

**対象**: `coverZipViewer/ImageManager.swift:70`

`decodeCachePolicy` が computed property で、デコードごとに
`AppSettings.shared.imageDecodeCachePolicy`（UserDefaults読み）を叩いている。
`loadImages` 時に読んで stored property に保持し、設定変更通知
（`CZDistributedNotifications.settingsChanged` 受信時に PreviewViewController から）で更新する。

### C-3. サムネイル拡張フォールバック経路の再パース排除

**対象**: `coverZipExtension/ThumbnailProvider.swift`

`firstImageThumbnail` が nil を返した場合のフォールバックで `CZZip.firstImageData(from: url, ...)`
を呼んでおり、ZIPファイルの再読込 + CD再パース + 表紙再選定が走る。
`CZZip` に「`Data` とパース済みエントリを受け取るオーバーロード」を追加するか、
`firstImageThumbnail` 内でサムネイル生成失敗時に元データを返せるよう
戻り値を `enum`（`.thumbnail(CGImage)` / `.rawData(Data)` / `.none`）にして1パスで完結させる。

### C-4. `ImageFileFilter.isImagePath` の軽量化（任意）

`lowercased()` で全文字列を毎回小文字化している。エントリ数の多いZIPで A-1/A-4 後も
プロファイルに残るようであれば、拡張子部分のみの比較
（`utf8` 末尾比較 or `caseInsensitiveCompare`）に変更。優先度は低い。

---

## 計測インフラ（A群着手前に実施）

実装の効果を定量化するため、最初に以下の signpost を追加する
（既存の `performanceLog`: subsystem `com.dmng.CoverZip.coverZipViewer`, category `Performance` を流用）:

1. `preparePreviewOfFile`: begin/end（ZIPオープン→初期表示準備完了）
2. `zipParse`: `CZZip.imageEntryInfoList` の begin/end（CDパース + ソート）
3. `extractAndDecode`: `ImageManager.getImageAtIndex` のキャッシュミス時 begin/end
   （`index` と `maxPixelSize` を引数に記録）
4. 既存の `displayCurrentImage` / `layerCacheHit` / `layerCacheMiss` は維持

計測手順（修正前にベースラインを取得し、各フェーズ後に同条件で再計測):

```bash
# サムネイル生成（エントリ数多 / 高解像度 / 非圧縮 の3種のZIPで）
qlmanage -r && time qlmanage -t path/to/test.zip

# プレビュー（Instruments の os_signpost テンプレートで上記区間を確認）
qlmanage -p path/to/test.zip
```

テスト用ZIPは最低3種用意する: ①1,000ページ級の多エントリZIP、
②1ページ数MBの高解像度ZIP、③非圧縮（store）ZIP。

---

## 実装順序とコミット粒度

| フェーズ | 項目 | 理由 |
|---------|------|------|
| 0 | 計測インフラ + ベースライン計測 | 効果の定量化 |
| 1 | A-3（正規表現キャッシュ） | 最小工数・最小リスク・効果大 |
| 2 | A-1（ポインタ読み） | ZipCoreに閉じる。A-2の前提となるヘルパーを作る |
| 3 | A-2（一発展開 + uncompressedSize） | A-1のヘルパーを利用 |
| 4 | A-4（ソートキー事前計算） | ZipCore/NaturalSortに閉じる |
| 5 | A-5（初回二重デコード解消） | ImageManager/PreviewVCにまたがるため計測必須 |
| 6 | B-1 → B-2 → B-3 → B-4 | UI挙動に絡むため1項目ずつ確認しながら |
| 7 | C-1〜C-4 | 仕上げ |

各フェーズ共通の完了条件:
- `xcodebuild -project CoverZip.xcodeproj -scheme CoverZip build CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` が成功
- `coverZipExtension` / `coverZipViewer` スキームも同様にビルド成功
- 上記3種のテストZIPで `qlmanage -t` / `qlmanage -p` の表示・ページ順・ページ送りが修正前と同一
- ZipCore 変更フェーズ（1〜4）は、ソート順・表紙選定結果が修正前と完全一致すること
  （ファイル名リストのスナップショット比較）

## 回帰リスクが高い箇所（実装時に特に注意）

- **A-1/A-2**: data descriptor（gpFlag bit3）付きZIP、CDとローカルヘッダでサイズが食い違うZIP、
  壊れたZIP（範囲外オフセット）でクラッシュしないこと。現行の境界チェックをすべて維持する。
- **A-4**: `localizedCompare` による最終タイブレークの互換。日本語ファイル名で順序検証。
- **A-5**: QuickLookホスト（Finderスペースキー / カラムビュー / 内蔵ビューア）それぞれで
  初期サイズの取得タイミングが異なる。3経路すべてで初回表示を確認。
- **B-1**: CALayerのバックグラウンド生成は「ツリー未アタッチ」が前提。
  生成済みレイヤーを使い回す箇所（`setPrerenderedLayer` は `contents` のみコピーして
  新レイヤーに載せる実装なので問題ない）を変えないこと。
- **B-2**: Extension と内蔵ビューアは別プロセス。メモリキャッシュ導入後も
  「読み出しは毎回 UserDefaults から」にするか、プロセス起動時刻以降の自プロセス書き込みのみ
  キャッシュに反映する設計とし、別プロセスの履歴を上書きで消さないよう
  `flush` 時に再読込→マージしてから書く。
