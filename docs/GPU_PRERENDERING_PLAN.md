# GPU事前レンダリング再実装計画（強化版）

## 背景と方針

過去の Phase 1 実装（`dbdc39a`）は、単ページでのみ部分的に機能し、見開き未適用・スレッド安全性・計測設計の面で課題が残った。  
このため本計画は、**いったん `git revert dbdc39a` で戻した前提で、段階導入で再実装**する。

本計画の最優先は次の3点。
- 単ページ/見開きの両方で、同一の仕組みで事前レンダリングを適用する
- スレッド安全性を明確にした上で実装する
- 効果を計測で判定し、Phase 2 以降に進む条件を定義する

**追加方針（最重要）**:  
大判画像ZIPでの遅延を抑えるため、Phase 1 は「フル解像度デコード禁止」を前提とする。  
ディスプレイ表示に必要なピクセル数まで ImageIO で縮小デコードしてから GPU キャッシュへ載せる。

## 目標と非目標

### 目標
- ページ切り替え時の体感遅延を低減する（単ページ・見開き両方）
- 現行UI/操作仕様（読み方向、見開き補正、スライドショー）を壊さない
- メモリ上限を管理し、メモリ圧迫時は自動退避できる

### 非目標（今回やらない）
- Metal による全面置換
- IOSurface 最適化
- 画像デコード方式の大規模刷新

## 成功指標（Go/No-Go 判定）

| 指標 | 合格ライン | 計測方法 |
|------|------------|----------|
| ページ切替レイテンシ p95 | 単ページ 25ms以下、見開き 35ms以下 | `os_signpost` + Instruments |
| FPS（アニメ中） | 55fps以上 | Core Animation |
| メモリ増加量 | ベースライン比 +50%以内 | Memory Report |
| 機能回帰 | 重大回帰 0 件 | 手動テスト表 |

上記を満たさない場合は、Phase 2 に進まず Phase 1 を改善する。

## 計測プロトコル（実装前に固定）

### 測定シナリオ
- シナリオA: 単ページで 200 ページを連続送り
- シナリオB: 見開き（RTL/LTR 各1回）で 200 ページを連続送り
- シナリオC: ウィンドウサイズ変更直後に 50 ページ送り

### 収集ログ
- `displayCurrentImage` 開始/終了
- レイヤーキャッシュ hit/miss
- 画像デコード時間
- 縮小デコード後のピクセルサイズ（width/height）
- 縮小率（原寸→表示用）
- メモリ圧迫時の退避発生回数

### ベースライン
- `revert` 後の現行実装で先に3シナリオを計測
- 同一ZIP・同一端末・同一表示倍率で比較

## アーキテクチャ設計（Phase 1 再実装）

### データフロー

```
[ZIP展開] -> [downsample decode(ImageIO Thumbnail)] -> [PrerenderLayerEntry作成]
                                                    -> [LayerCacheに保存]
                                                    -> [表示時はcached layerを直接適用]
                                                    -> [miss時のみ従来経路へフォールバック]
```

### 縮小デコード戦略（Phase 1 必須）
- フル解像度の `CGImageSourceCreateImageAtIndex` を既定経路で使わない
- `CGImageSourceCreateThumbnailAtIndex` を使い、`kCGImageSourceThumbnailMaxPixelSize` を指定して縮小デコードする
- EXIF向き補正のため `kCGImageSourceCreateThumbnailWithTransform = true`
- 常にデコードするため `kCGImageSourceCreateThumbnailFromImageAlways = true`

`targetPixelSize` 算出:
- `displayPointSize = imageView.bounds.size`
- `displayScale = backingScaleFactor`
- `singlePageWidth = displayPointSize.width`
- `spreadPageWidth = displayPointSize.width / 2`（見開き時）
- `targetHeight = displayPointSize.height`
- `targetWidth = singlePageWidth`（単ページ）または `spreadPageWidth`（見開き）
- `targetPixelMax = max(targetWidth, targetHeight) * displayScale`

補足:
- `targetPixelMax` は 64px バケットに丸める（キャッシュの安定化）
- ズーム機能を将来追加する場合は「高解像度再デコード」を別経路で用意する

### キャッシュキー設計
- 単ページ: `(pageIndex, widthBucket, heightBucket, scale)`
- 見開き: `(leftIndex, rightIndex, widthBucket, heightBucket, scale, readingDirection, spreadOffset)`

`widthBucket/heightBucket` は小刻みなリサイズ乱発を防ぐため 64px 単位で丸める。

### スレッドモデル
- `decodeQueue`（並列可）: ZIP展開/デコード/リサイズ
- `layerBuildQueue`（シリアル）: キャッシュ状態更新
- MainActor: `CALayer` 生成・UI適用・`contents` 変更

ルール:
- `CALayer` の生成/変更は MainActor 限定
- `currentIndex`/`targetDisplaySize` を含む共有状態は `layerBuildQueue` 経由でのみ更新
- UIコールバックは「現在表示キーと一致」した場合のみ反映（古い非同期結果を破棄）

### 表示戦略
- `NSImageView` ごとに表示用サブレイヤーを1枚だけ保持し、毎回作り直さない
- 表示時は `cachedLayer.contents` を転写するのではなく、**再利用可能な表示レイヤーへ最小更新**
- miss時は必ず既存の `setImageSafely` へフォールバック

### 先読み戦略
- 単ページ: `current, -1, +1, +2`
- 見開き: 次の見開きセット1組を追加で先読み
- キャッシュ上限:
  - 単ページレイヤー 5
  - 見開きレイヤーセット 3
- メモリ圧迫通知時は `current` のみ残して退避

## 実装ステップ（段階導入）

### Step 0: ロールバック
- `git revert dbdc39a`
- ビルドと既存操作の健全性確認

### Step 1: 計測基盤
- `os_signpost` とキャッシュ hit/miss ログを追加
- ベースラインを取得し `docs` に記録

### Step 2: 単ページのみ再実装
- `ImageManager` に縮小デコード経路を実装（単ページ）
- `PrerenderedLayerCache` をシンプルに作り直す（単ページのみ）
- `PreviewViewController` 単ページ表示に限定導入
- 単ページシナリオA/Cで合格判定

### Step 3: 見開き対応
- 見開き時の半幅 `targetPixelSize` で縮小デコード
- 見開きキーとキャッシュ実装
- RTL/LTR、見開き補正（offset）をキーに反映
- シナリオBで合格判定

### Step 4: メモリ圧迫・サイズ変更の安定化
- サイズ変更時のバケット再計算と古いエントリ廃棄
- メモリ圧迫時の退避ロジックと復帰確認

### Step 5: リリース判断
- 成功指標の最終判定
- 未達なら Phase 1 改善継続、達成なら Phase 2 検討に進む

## 変更対象ファイル（Phase 1）

- `coverZipViewer/ImageManager.swift`
  - 先読み対象の管理
  - 縮小デコード（ImageIO Thumbnail）実装
  - 事前レンダリング要求APIの窓口
- `coverZipViewer/PreviewViewController.swift`
  - 単/見開きでの表示切替
  - フォールバック制御
  - 計測ログ
- `coverZipViewer/PrerenderedLayerCache.swift`（再作成）
  - キー管理、LRU、メモリ圧迫時退避
- `docs/GPU_PRERENDERING_PLAN.md`
  - 計測結果と判定記録の追記

## テスト観点

### 機能テスト
- 単ページ/見開きでページ送り・戻しが正常
- RTL/LTR 切替後も表示順が正しい
- 見開き補正（offset）有効時も正しく表示
- スライドショー中のページ遷移で表示破綻しない

### 安定性テスト
- 連続ページ送り 500 回でクラッシュしない
- ウィンドウリサイズ連打中も表示が破綻しない
- メモリ圧迫通知後に表示が復旧する

### 回帰テスト
- 画像がないZIP、破損ZIPで従来通りフォールバック
- 履歴復元（ページ・表示モード・綴じ方向）に影響しない
- 超高解像度画像ZIPで、表示が粗すぎないこと（目視許容範囲）

## リスクと軽減策

| リスク | 影響 | 軽減策 |
|--------|------|--------|
| 非同期結果の逆転適用 | ちらつき/誤表示 | 表示キー一致チェック |
| メモリ増大 | 処理落ち/クラッシュ | バケット化 + 固定上限 + 圧迫時退避 |
| 見開きキー不足 | キャッシュ誤ヒット | readingDirection/offsetをキー化 |
| 縮小しすぎによる画質低下 | 可読性低下 | scale反映 + バケット最小値設定 + 必要時再デコード |
| 効果が小さい | 工数超過 | Step 2 で計測ゲートを設置 |

## 実装前TODO（この順で実施）

1. [ ] `dbdc39a` を `git revert` して作業ブランチをクリーン化
2. [ ] ベースライン計測（A/B/C）を取得
3. [ ] `ImageManager` の縮小デコード設計（targetPixelSize/バケット）を確定
4. [ ] 単ページの縮小デコード + 事前レンダリング実装で計測合格を確認
5. [ ] 見開き縮小デコード + 見開きキャッシュ実装（RTL/LTR/offset）を検証
6. [ ] メモリ圧迫・リサイズ安定化を実装
7. [ ] 計測結果を本ドキュメントに反映し、Phase 2 判定を実施

## 将来計画（Phase 2/3 の判断条件）

### Phase 2（IOSurface）に進む条件
- Phase 1 合格後も p95 が目標未達
- GPU転送が依然として支配的と計測で確認

### Phase 3（Metal）に進む条件
- Phase 2 実施後も要件未達
- UI/保守性コスト増を受容可能と判断
