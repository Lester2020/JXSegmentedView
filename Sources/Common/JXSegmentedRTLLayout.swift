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
        segmentedViewShouldRTLLayout(relativeTo: nil)
    }

    /// 优先看 `host` 所在窗口的布局方向，避免读到调试浮窗等别的 key window。
    /// `host` 必须是没有被改成 `forceLeftToRight` 的容器，不能传已经镜像过的 collection / scroll。
    func segmentedViewShouldRTLLayout(relativeTo host: UIView?) -> Bool {
        if let host {
            if #available(iOS 10.0, *), host.traitCollection.layoutDirection == .rightToLeft {
                return true
            }
            if host.effectiveUserInterfaceLayoutDirection == .rightToLeft {
                return true
            }
        }
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
        segmentedViewSetMirrored(true, on: view)
    }

    /// 带 `scaleX(-1)` 时直接改 `frame` 会把翻转清掉。先卸掉再设 frame，调用方负责把翻转加回去。
    func segmentedViewSetFrame(_ frame: CGRect, on view: UIView) {
        let mirrored = view.transform.a < 0
        if mirrored {
            view.transform = .identity
        }
        view.frame = frame
        if mirrored {
            view.transform = CGAffineTransform(scaleX: -1, y: 1)
        }
    }

    /// 只在状态变化时改 transform，避免 `layoutSubviews` 里来回触发布局。
    func segmentedViewSetMirrored(_ mirrored: Bool, on view: UIView?) {
        guard let view else { return }
        let currentlyMirrored = view.transform.a < 0
        guard currentlyMirrored != mirrored else { return }
        view.transform = mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
    }

    func segmentedViewClearHorizontalFlip(on view: UIView?) {
        guard let view else { return }
        view.semanticContentAttribute = .unspecified
        segmentedViewSetMirrored(false, on: view)
        // 非 RTL 时钉回 LTR，避免上次钉的 RTL 留在嵌入列表上。只写不读。
        segmentedViewPinLayoutDirection(.leftToRight, on: view)
    }

    /// 频道条 / 横向分页：先钉成 LTR，再翻转。页码仍是 `index * width`。
    /// iOS 17 祖先的 `traitOverrides.layoutDirection` 会盖过 `forceLeftToRight`，
    /// 分页自己先按 RTL 排、再被翻转，视觉上又变回从左到右。
    func segmentedViewApplyMirrorPagingLayout(to view: UIView?, host: UIView? = nil) {
        guard let view else { return }
        let rtl = segmentedViewShouldRTLLayout(relativeTo: host)
        JXSegmentedRTLContext.mirrorPaging = rtl
        guard rtl else {
            segmentedViewClearHorizontalFlip(on: view)
            return
        }
        segmentedViewPinLayoutDirection(.leftToRight, on: view)
        view.semanticContentAttribute = .forceLeftToRight
        segmentedView(horizontalFlipForView: view)
    }

    /// 嵌入列表：同样翻转，抵消分页 scroll 的镜像，文字不颠倒。
    /// 方向必须钉成 RTL。若也钉成 LTR，两次翻转抵消后 Cell 会按 LTR 排（缩略图一直在右）。
    func segmentedViewApplyEmbeddedListRTLLayout(to view: UIView?, host: UIView? = nil) {
        guard let view else { return }
        guard segmentedViewShouldRTLLayout(relativeTo: host) else {
            segmentedViewClearHorizontalFlip(on: view)
            return
        }
        segmentedViewPinLayoutDirection(.rightToLeft, on: view)
        view.semanticContentAttribute = .forceRightToLeft
        segmentedView(horizontalFlipForView: view)
    }

    /// iOS 17+ 用视图自己的 `traitOverrides` 压过窗口上的布局方向。iOS 16 没有该 API，靠 semantic。
    func segmentedViewPinLayoutDirection(_ direction: UITraitEnvironmentLayoutDirection, on view: UIView) {
        if #available(iOS 17.0, *) {
            view.traitOverrides.layoutDirection = direction
        }
    }
}

enum JXSegmentedRTLContext {
    /// 频道条 / 分页正在镜像。Cell 在 `layoutSubviews` 里跟上，避免创建时方向还没写好。
    static var mirrorPaging = false

    static func resolvedKeyWindow() -> UIWindow? {
        if #available(iOS 13.0, *) {
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
            let normalWindows = windows.filter { $0.windowLevel == .normal }
            let candidates = normalWindows.isEmpty ? windows : normalWindows
            if let window = candidates.first(where: \.isKeyWindow) ?? candidates.first {
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
        syncMirrorWithPagingLayout()
    }

    override func layoutSubviews() {
        syncMirrorWithPagingLayout()
        super.layoutSubviews()
    }

    /// 分页容器翻转后，Cell 再翻一次，文字才是正的。
    private func syncMirrorWithPagingLayout() {
        let mirrored = JXSegmentedRTLContext.mirrorPaging
        segmentedViewSetMirrored(mirrored, on: self)
        segmentedViewSetMirrored(mirrored, on: contentView)
    }
}
