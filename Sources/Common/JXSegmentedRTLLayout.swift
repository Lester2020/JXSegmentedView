//
//  JXSegmentedRTLLayout.swift
//  JXSegmentedView
//
//  Created by blue on 2020/6/18.
//  Copyright © 2020 jiaxin. All rights reserved.
//

import UIKit

public protocol JXSegmentedViewRTLCompatible: AnyObject {
    func segmentedViewShouldRTLLayout() -> Bool
    func segmentedView(horizontalFlipForView view: UIView?)
}

public extension JXSegmentedViewRTLCompatible {

    /// 是否按 RTL 排布。
    ///
    /// - iOS 16：宿主用 `UIView.appearance().semanticContentAttribute`（以及 window semantic）。
    /// - iOS 17+：还可以读 `traitCollection.layoutDirection`（Scene / window `traitOverrides` 的结果）。
    /// 只读 trait，禁止读 `traitOverrides.layoutDirection` getter（未设置时会抛异常）。
    func segmentedViewShouldRTLLayout() -> Bool {
        if UIView.userInterfaceLayoutDirection(for: UIView.appearance().semanticContentAttribute) == .rightToLeft {
            return true
        }
        if let window = JXSegmentedRTLContext.resolvedKeyWindow() {
            if #available(iOS 10.0, *), window.traitCollection.layoutDirection == .rightToLeft {
                return true
            }
            if window.effectiveUserInterfaceLayoutDirection == .rightToLeft {
                return true
            }
        }
        return false
    }

    /// 水平镜像。频道条、分页、嵌入列表都用手算 frame，不能只靠 semantic。
    func segmentedView(horizontalFlipForView view: UIView?) {
        guard let view else { return }
        view.transform = CGAffineTransform(scaleX: -1, y: 1)
    }

    func segmentedViewClearHorizontalFlip(on view: UIView?) {
        guard let view else { return }
        view.semanticContentAttribute = .unspecified
        view.transform = .identity
    }

    /// 频道条 / 横向分页：`forceLeftToRight` 后再翻转，页码仍是 `index * width`。
    func segmentedViewApplyMirrorPagingLayout(to view: UIView?) {
        guard let view else { return }
        guard segmentedViewShouldRTLLayout() else {
            segmentedViewClearHorizontalFlip(on: view)
            return
        }
        view.semanticContentAttribute = .forceLeftToRight
        segmentedView(horizontalFlipForView: view)
    }

    /// 嵌入列表：同样翻转，抵消分页 scroll 的镜像，文字不颠倒。
    /// 语义必须是 RTL。若也设 `forceLeftToRight`，两次翻转抵消后 Cell 会按 LTR 排（缩略图一直在右）。
    func segmentedViewApplyEmbeddedListRTLLayout(to view: UIView?) {
        guard let view else { return }
        guard segmentedViewShouldRTLLayout() else {
            segmentedViewClearHorizontalFlip(on: view)
            return
        }
        view.semanticContentAttribute = .forceRightToLeft
        segmentedView(horizontalFlipForView: view)
    }
}

private enum JXSegmentedRTLContext {
    static func resolvedKeyWindow() -> UIWindow? {
        if #available(iOS 13.0, *) {
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
            if let window = windows.first(where: \.isKeyWindow) ?? windows.first {
                return window
            }
        }
        return UIApplication.shared.keyWindow
    }
}

class JXSegmentedRTLCollectionCell: UICollectionViewCell, JXSegmentedViewRTLCompatible {

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    func commonInit() {
        if segmentedViewShouldRTLLayout() {
            segmentedView(horizontalFlipForView: self)
            segmentedView(horizontalFlipForView: contentView)
        }
    }
}
