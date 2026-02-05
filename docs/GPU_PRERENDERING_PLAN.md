# GPU事前レンダリング計画

## 概要

現在のプリロード実装では、NSImageオブジェクトまでのキャッシュを行っているが、GPUへのテクスチャアップロードは表示時に発生するため、体感速度の向上が限定的である。本計画では、GPUレベルでの事前レンダリングを実装し、ページ切り替え時の表示速度を大幅に改善する。

## 現状分析

### 現在のデータフロー

```
[ZIP展開] → [CGImageSourceデコード] → [NSImage作成] → [リサイズ]
                    ↑ プリロードの範囲 ↑
                                                            ↓
                                              [NSImageView.image設定]
                                                            ↓
                                              [CALayerテクスチャアップロード] ← ボトルネック
                                                            ↓
                                                      [画面描画]
```

### ボトルネックの特定

| 処理 | 実行タイミング | 負荷 |
|------|---------------|------|
| ZIP展開 | プリロード時 | 中 |
| 画像デコード | プリロード時 | 高（CPU） |
| リサイズ | プリロード時 | 中（CPU） |
| **テクスチャアップロード** | **表示時** | **高（GPU転送）** |
| 描画 | 表示時 | 低 |

**問題**: 最も重い「テクスチャアップロード」がプリロードされていない

---

## 改善計画

### Phase 1: CALayerの事前準備（推奨・低リスク）

**目標**: 表示時のテクスチャアップロードを排除

**実装概要**:
```swift
// 新規クラス: PrerenderedLayerCache
class PrerenderedLayerCache {
    private var layerCache: [Int: CALayer] = [:]

    func prerenderLayer(for index: Int, image: NSImage, size: CGSize) {
        let layer = CALayer()
        layer.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        layer.contentsGravity = .resizeAspect
        layer.frame = CGRect(origin: .zero, size: size)

        // 強制的にGPUにアップロード
        layer.setNeedsDisplay()
        layer.displayIfNeeded()

        layerCache[index] = layer
    }

    func getPrerenderedLayer(for index: Int) -> CALayer? {
        return layerCache[index]
    }
}
```

**変更点**:
- `ImageManager.swift`: NSImageに加えて事前レンダリング済みCALayerもキャッシュ
- `PreviewViewController.swift`: 表示時にNSImageView.imageではなく、レイヤー入れ替えで表示

**メリット**:
- 既存アーキテクチャへの影響が小さい
- Metalの知識不要
- 段階的な導入が可能

**デメリット**:
- メモリ使用量増加（CALayer + テクスチャ分）
- 完全なGPU最適化ではない

**見積もり工数**: 中

---

### Phase 2: IOSurfaceによるゼロコピー最適化（中リスク）

**目標**: CPU-GPU間のデータ転送を最小化

**実装概要**:
```swift
import IOSurface

class IOSurfaceImageCache {
    func createIOSurfaceBackedImage(from data: Data, size: CGSize) -> CGImage? {
        // IOSurfaceを作成
        let properties: [IOSurfacePropertyKey: Any] = [
            .width: Int(size.width),
            .height: Int(size.height),
            .bytesPerElement: 4,
            .pixelFormat: kCVPixelFormatType_32BGRA
        ]

        guard let surface = IOSurface(properties: properties) else { return nil }

        // CGImageをIOSurfaceバッキングで作成
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: IOSurfaceGetBaseAddress(surface),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: IOSurfaceGetBytesPerRow(surface),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // 画像を描画
        // ...

        return context.makeImage()
    }
}
```

**変更点**:
- 新規: `Shared/IOSurfaceImageCache.swift`
- `ImageManager.swift`: IOSurfaceベースの画像生成に対応
- CALayer.contentsにIOSurfaceを直接設定可能

**メリット**:
- GPUメモリへの直接マッピング
- コピー不要でテクスチャとして使用可能
- macOS標準APIで実現可能

**デメリット**:
- IOSurface APIの複雑さ
- メモリ管理が難しい
- App Extensionでの制約確認が必要

**見積もり工数**: 中〜高

---

### Phase 3: Metal統合（高リスク・高効果）

**目標**: 完全なGPU駆動のレンダリングパイプライン

#### Phase 3a: CAMetalLayerによる描画

**実装概要**:
```swift
import MetalKit

class MetalImageRenderer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var textureCache: [Int: MTLTexture] = [:]

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = queue
    }

    func prerenderTexture(for index: Int, image: CGImage) {
        let textureLoader = MTKTextureLoader(device: device)
        if let texture = try? textureLoader.newTexture(cgImage: image, options: [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue
        ]) {
            textureCache[index] = texture
        }
    }

    func renderToLayer(_ metalLayer: CAMetalLayer, textureIndex: Int) {
        guard let texture = textureCache[textureIndex],
              let drawable = metalLayer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // レンダリングパス設定
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        // 描画コマンド
        // ...

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
```

**変更点**:
- 新規: `coverZipViewer/MetalImageRenderer.swift`
- 新規: `coverZipViewer/Shaders.metal`（シェーダー）
- `PreviewViewController.swift`: NSImageViewをCAMetalLayer/MTKViewに置換

#### Phase 3b: GPUデコード・リサイズ

**実装概要**:
```swift
// Metal Performance Shadersを使用したリサイズ
import MetalPerformanceShaders

func resizeOnGPU(source: MTLTexture, targetSize: CGSize) -> MTLTexture? {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: source.pixelFormat,
        width: Int(targetSize.width),
        height: Int(targetSize.height),
        mipmapped: false
    )
    descriptor.usage = [.shaderRead, .shaderWrite]

    guard let destination = device.makeTexture(descriptor: descriptor),
          let commandBuffer = commandQueue.makeCommandBuffer() else { return nil }

    let scaleFilter = MPSImageLanczosScale(device: device)
    scaleFilter.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: destination)

    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    return destination
}
```

**メリット**:
- 最高のパフォーマンス
- GPUでの並列処理
- 将来的な拡張性（HDR、アニメーション等）

**デメリット**:
- 大幅なアーキテクチャ変更
- Metalの専門知識が必要
- デバッグが困難
- App Extension制約の確認が必要

**見積もり工数**: 高

---

## 推奨実装順序

```
Phase 1 (CALayer事前準備)
    ↓ 効果測定
Phase 2 (IOSurface最適化) ← 効果が不十分な場合
    ↓ 効果測定
Phase 3 (Metal統合) ← さらなる最適化が必要な場合
```

### Phase 1で期待される効果

| 指標 | 現状 | Phase 1後 |
|------|------|-----------|
| ページ切り替え遅延 | 50-100ms | 10-20ms |
| 体感 | カクつきあり | スムーズ |
| メモリ使用量 | 基準 | +20-30% |

---

## 技術的考慮事項

### App Extension制約

| API | Thumbnail Extension | Preview Extension |
|-----|---------------------|-------------------|
| CALayer | ✅ | ✅ |
| IOSurface | ⚠️ 要検証 | ⚠️ 要検証 |
| Metal | ⚠️ 要検証 | ✅（おそらく可） |

### メモリ管理

```
Phase 1のキャッシュ戦略:
- 事前レンダリング済みCALayer: 最大5枚（現在±2ページ）
- リサイズ済みNSImage: 現状維持（20枚）
- 元画像NSImage: 現状維持（10枚）

推定追加メモリ使用量:
- 4K画像1枚 ≈ 32MB（RGBA 3840x2160）
- 5枚のCALayerテクスチャ ≈ 160MB追加
```

### スレッド安全性

```swift
// CALayerの操作はメインスレッドで行う必要がある
DispatchQueue.main.async {
    self.swapPrerenderedLayer(for: index)
}

// テクスチャ作成はバックグラウンドで可能
DispatchQueue.global(qos: .userInitiated).async {
    let layer = self.prerenderLayer(for: index, image: image)
    DispatchQueue.main.async {
        self.cachePrerenderedLayer(layer, for: index)
    }
}
```

---

## 実装ファイル構成（Phase 1）

```
coverZipViewer/
├── PreviewViewController.swift  # 変更: レイヤー入れ替えロジック追加
├── ImageManager.swift           # 変更: 事前レンダリング呼び出し追加
├── PrerenderedLayerCache.swift  # 新規: CALayerキャッシュ管理
└── ...

Shared/
├── ImageUtilities.swift         # 変更: CGImage変換ヘルパー追加
└── ...
```

---

## 成功指標

1. **ページ切り替え遅延**: 50ms以下
2. **FPS**: 60fps維持（ページ送りアニメーション中）
3. **メモリ使用量**: 基準+50%以下
4. **CPU使用率**: ページ切り替え時5%以下

---

## リスクと軽減策

| リスク | 影響 | 軽減策 |
|--------|------|--------|
| メモリ不足 | クラッシュ | 動的キャッシュサイズ調整 |
| App Extension制約 | 機能制限 | フォールバック実装 |
| レイヤー同期問題 | 表示不具合 | メインスレッド強制 |
| Retina対応漏れ | ぼやけ | backingScaleFactor考慮 |

---

## 次のステップ

1. [ ] Phase 1のプロトタイプ実装
2. [ ] パフォーマンス測定環境の構築
3. [ ] 効果測定とボトルネック再分析
4. [ ] Phase 2以降の判断
