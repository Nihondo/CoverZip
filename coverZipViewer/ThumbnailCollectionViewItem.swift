//
//  ThumbnailCollectionViewItem.swift
//  coverZipViewer
//

import Cocoa

/// サムネイルリスト用のNSCollectionViewItemサブクラス
class ThumbnailCollectionViewItem: NSCollectionViewItem {

    static let identifier = NSUserInterfaceItemIdentifier("ThumbnailCollectionViewItem")

    private let thumbnailImageView: NSImageView = {
        let iv = NSImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.imageAlignment = .alignCenter
        iv.wantsLayer = true
        return iv
    }()

    private let highlightView: NSView = {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true
        v.layer?.cornerRadius = 3
        v.layer?.borderWidth = 2
        v.layer?.borderColor = NSColor.controlAccentColor.cgColor
        v.isHidden = true
        return v
    }()

    override func loadView() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        self.view = container

        container.addSubview(thumbnailImageView)
        container.addSubview(highlightView)

        NSLayoutConstraint.activate([
            thumbnailImageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            thumbnailImageView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
            thumbnailImageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            thumbnailImageView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),

            highlightView.leadingAnchor.constraint(equalTo: thumbnailImageView.leadingAnchor),
            highlightView.trailingAnchor.constraint(equalTo: thumbnailImageView.trailingAnchor),
            highlightView.topAnchor.constraint(equalTo: thumbnailImageView.topAnchor),
            highlightView.bottomAnchor.constraint(equalTo: thumbnailImageView.bottomAnchor),
        ])
    }

    func configure(image: NSImage?) {
        thumbnailImageView.image = image
    }

    override var isSelected: Bool {
        didSet {
            highlightView.isHidden = !isSelected
        }
    }
}
