//
//  ImageUtilities.swift
//  CoverZip Shared
//
//  全ターゲットで共有する画像処理ユーティリティ
//

import Foundation
import CoreGraphics

#if os(macOS)
import AppKit
#endif

/// 画像処理に関する共通ユーティリティ
public enum CZImageUtilities {

    /// 画像の縦横比を維持したサムネイルサイズを計算する
    /// 最大サイズの制限内で、元画像の縦横比を保持し、クロップされないよう適切にスケーリングする
    ///
    /// - Parameters:
    ///   - imageSize: 元画像のサイズ
    ///   - maxSize: 最大許容サイズ
    /// - Returns: 計算されたサムネイルサイズ
    public static func calculateFitSize(for imageSize: CGSize, within maxSize: CGSize) -> CGSize {
        let imageAspectRatio = imageSize.width / imageSize.height
        let maxAspectRatio = maxSize.width / maxSize.height

        var resultWidth: CGFloat
        var resultHeight: CGFloat

        if imageAspectRatio > maxAspectRatio {
            // 画像が最大サイズより横長の場合、幅を基準にスケーリング
            resultWidth = maxSize.width
            resultHeight = resultWidth / imageAspectRatio
        } else {
            // 画像が最大サイズより縦長または同じ縦横比の場合、高さを基準にスケーリング
            resultHeight = maxSize.height
            resultWidth = resultHeight * imageAspectRatio
        }

        return CGSize(width: resultWidth, height: resultHeight)
    }

    /// 画像を適切にスケーリングしてキャンバスの中央に配置するための矩形を計算する
    /// 画像の縦横比を維持しながら、キャンバスサイズ内に収まるように縮小する
    ///
    /// - Parameters:
    ///   - imageSize: 元画像のサイズ
    ///   - canvasSize: キャンバスのサイズ
    /// - Returns: スケーリングされ中央配置された画像の矩形
    public static func calculateCenteredRect(for imageSize: CGSize, in canvasSize: CGSize) -> CGRect {
        // まず適切なサイズを計算
        let fitSize = calculateFitSize(for: imageSize, within: canvasSize)

        // 中央配置のための座標を計算
        let x = (canvasSize.width - fitSize.width) / 2
        let y = (canvasSize.height - fitSize.height) / 2

        return CGRect(x: x, y: y, width: fitSize.width, height: fitSize.height)
    }
}
