import Foundation
import UIKit
import Display
import TelegramPresentationData
import ComponentFlow
import ComponentDisplayAdapters
import GlassBackgroundComponent
import MultilineTextComponent
import LottieComponent
import UIKitRuntimeUtils
import BundleIconComponent
import TextBadgeComponent
import GlassImitation


public final class TabBarComponent: Component {
    public final class Item: Equatable {
        public let item: UITabBarItem
        public let action: (Bool) -> Void
        public let contextAction: ((ContextGesture, ContextExtractedContentContainingView) -> Void)?
        
        fileprivate var id: AnyHashable {
            return AnyHashable(ObjectIdentifier(self.item))
        }
        
        public init(item: UITabBarItem, action: @escaping (Bool) -> Void, contextAction: ((ContextGesture, ContextExtractedContentContainingView) -> Void)?) {
            self.item = item
            self.action = action
            self.contextAction = contextAction
        }
        
        public static func ==(lhs: Item, rhs: Item) -> Bool {
            if lhs === rhs {
                return true
            }
            if lhs.item !== rhs.item {
                return false
            }
            if (lhs.contextAction == nil) != (rhs.contextAction == nil) {
                return false
            }
            return true
        }
    }
    
    public let theme: PresentationTheme
    public let items: [Item]
    public let selectedId: AnyHashable?
    public let isTablet: Bool
    
    public init(
        theme: PresentationTheme,
        items: [Item],
        selectedId: AnyHashable?,
        isTablet: Bool
    ) {
        self.theme = theme
        self.items = items
        self.selectedId = selectedId
        self.isTablet = isTablet
    }
    
    public static func ==(lhs: TabBarComponent, rhs: TabBarComponent) -> Bool {
        if lhs.theme !== rhs.theme {
            return false
        }
        if lhs.items != rhs.items {
            return false
        }
        if lhs.selectedId != rhs.selectedId {
            return false
        }
        if lhs.isTablet != rhs.isTablet {
            return false
        }
        return true
    }
    
    public final class View: UIView, UITabBarDelegate, UIGestureRecognizerDelegate {
        private let backgroundView: GlassBackgroundView
        private let selectionView: GlassBackgroundView.ContentImageView
        private let itemsContentView: UIView
        private let defaultItemsContainerView: UIView
        private let selectedItemsContainerView: UIView
        private let selectedItemsMaskView: UIView
        private let contextGestureContainerView: ContextControllerSourceView
        private let nativeTabBar: UITabBar?

        private let glassView: GlassView
        private var glassParametersTap: GlassParameters?
        private var glassParametersPan: GlassParameters?

        private var itemViews: [AnyHashable: ComponentView<Empty>] = [:]
        private var selectedItemViews: [AnyHashable: ComponentView<Empty>] = [:]

        private var itemWithActiveContextGesture: AnyHashable?

        private var component: TabBarComponent?
        private weak var state: EmptyComponentState?

        private var panGestureRecognizer: UIPanGestureRecognizer?
        private var panStartSelectedIndex: Int?
        private var panInitialAnimationCompleted: Bool = false
        private var skipScalePulse: Bool = false
        private var panStartLocation: CGPoint = .zero
        private let panBarMaxOffset: CGFloat = 5.0
        private var isPanGestureActive: Bool = false
        
        public override init(frame: CGRect) {
            self.backgroundView = GlassBackgroundView()
            self.selectionView = GlassBackgroundView.ContentImageView()
            self.glassView = GlassView(preset: .tabBarGlassTap, alwaysLiquid: false)
            self.glassView.captureMethod = .render
            self.glassView.isUserInteractionEnabled = false

            self.itemsContentView = GlassBackgroundView()
            self.itemsContentView.isUserInteractionEnabled = false
            self.itemsContentView.isOpaque = true
            // self.itemsContentView.backgroundColor = .white
            self.defaultItemsContainerView = UIView()
            self.defaultItemsContainerView.isUserInteractionEnabled = false
            self.selectedItemsContainerView = UIView()
            self.selectedItemsContainerView.isUserInteractionEnabled = false
            self.selectedItemsMaskView = UIView()
            self.selectedItemsMaskView.backgroundColor = .black
            self.selectedItemsContainerView.layer.mask = self.selectedItemsMaskView.layer

            self.contextGestureContainerView = ContextControllerSourceView()
            self.contextGestureContainerView.isGestureEnabled = true

            if #available(iOS 26.0, *) {
                let nativeTabBar = UITabBar()
                self.nativeTabBar = nativeTabBar
                
                let itemFont = Font.semibold(10.0)
                let itemColor: UIColor = .clear
                
                nativeTabBar.traitOverrides.verticalSizeClass = .compact
                nativeTabBar.traitOverrides.horizontalSizeClass = .compact
                nativeTabBar.standardAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                    .foregroundColor: itemColor,
                    .font: itemFont
                ]
                nativeTabBar.standardAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                    .foregroundColor: itemColor,
                    .font: itemFont
                ]
                nativeTabBar.standardAppearance.inlineLayoutAppearance.normal.titleTextAttributes = [
                    .foregroundColor: itemColor,
                    .font: itemFont
                ]
                nativeTabBar.standardAppearance.inlineLayoutAppearance.selected.titleTextAttributes = [
                    .foregroundColor: itemColor,
                    .font: itemFont
                ]
                nativeTabBar.standardAppearance.compactInlineLayoutAppearance.normal.titleTextAttributes = [
                    .foregroundColor: itemColor,
                    .font: itemFont
                ]
                nativeTabBar.standardAppearance.compactInlineLayoutAppearance.selected.titleTextAttributes = [
                    .foregroundColor: itemColor,
                    .font: itemFont
                ]
            } else {
                self.nativeTabBar = nil
            }
            
            super.init(frame: frame)
            
            if #available(iOS 17.0, *) {
                self.traitOverrides.verticalSizeClass = .compact
                self.traitOverrides.horizontalSizeClass = .compact
            }
            
            self.addSubview(self.contextGestureContainerView)

            if let nativeTabBar = self.nativeTabBar {
                self.contextGestureContainerView.addSubview(nativeTabBar)
                nativeTabBar.delegate = self
            } else {
                self.addSubview(self.backgroundView)
                self.backgroundView.contentView.addSubview(self.itemsContentView)
                
                self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.onTapGesture(_:))))

                let panGesture = UIPanGestureRecognizer(target: self, action: #selector(self.onPanGesture(_:)))
                panGesture.delegate = self
                self.addGestureRecognizer(panGesture)
                self.panGestureRecognizer = panGesture
            }
            
            self.contextGestureContainerView.shouldBegin = { [weak self] point in
                guard let self, let component = self.component else {
                    return false
                }
                if let panGesture = self.panGestureRecognizer, let contextGesture = self.contextGestureContainerView.contextGesture {
                    contextGesture.require(toFail: panGesture)
                }
                for (id, itemView) in self.itemViews {
                    if let itemView = itemView.view {
                        if self.convert(itemView.bounds, from: itemView).contains(point) {
                            guard let item = component.items.first(where: { $0.id == id }) else {
                                return false
                            }
                            if item.contextAction == nil {
                                return false
                            }
                            
                            self.itemWithActiveContextGesture = id
                            
                            let startPoint = point
                            self.contextGestureContainerView.contextGesture?.externalUpdated = { [weak self] _, point in
                                guard let self else {
                                    return
                                }
                                
                                let dist = sqrt(pow(startPoint.x - point.x, 2.0) + pow(startPoint.y - point.y, 2.0))
                                if dist > 10.0 {
                                    self.contextGestureContainerView.contextGesture?.cancel()
                                }
                            }
                            
                            return true
                        }
                    }
                }
                return false
            }
            self.contextGestureContainerView.customActivationProgress = { [weak self] _, _ in
                let _ = self
                return
                /*guard let self, let itemWithActiveContextGesture = self.itemWithActiveContextGesture else {
                    return
                }
                guard let itemView = self.itemViews[itemWithActiveContextGesture]?.view else {
                    return
                }
                let scaleSide = itemView.bounds.width
                let minScale: CGFloat = max(0.7, (scaleSide - 15.0) / scaleSide)
                let currentScale = 1.0 * (1.0 - progress) + minScale * progress

                switch update {
                case .update:
                    let sublayerTransform = CATransform3DScale(CATransform3DIdentity, currentScale, currentScale, 1.0)
                    itemView.layer.sublayerTransform = sublayerTransform
                case .begin:
                    let sublayerTransform = CATransform3DScale(CATransform3DIdentity, currentScale, currentScale, 1.0)
                    itemView.layer.sublayerTransform = sublayerTransform
                case .ended:
                    let sublayerTransform = CATransform3DScale(CATransform3DIdentity, currentScale, currentScale, 1.0)
                    let previousTransform = itemView.layer.sublayerTransform
                    itemView.layer.sublayerTransform = sublayerTransform

                    itemView.layer.animate(from: NSValue(caTransform3D: previousTransform), to: NSValue(caTransform3D: sublayerTransform), keyPath: "sublayerTransform", timingFunction: CAMediaTimingFunctionName.easeOut.rawValue, duration: 0.2)
                }*/
            }
            self.contextGestureContainerView.activated = { [weak self] gesture, _ in
                guard let self, let component = self.component else {
                    return
                }
                guard let itemWithActiveContextGesture = self.itemWithActiveContextGesture else {
                    return
                }
                
                var itemView: ItemComponent.View?
                if self.nativeTabBar != nil {
                    itemView = self.selectedItemViews[itemWithActiveContextGesture]?.view as? ItemComponent.View
                } else {
                    itemView = self.itemViews[itemWithActiveContextGesture]?.view as? ItemComponent.View
                }
                
                guard let itemView else {
                    return
                }
                
                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        return
                    }
                    if let nativeTabBar = self.nativeTabBar {
                        func cancelGestures(view: UIView) {
                            for recognizer in view.gestureRecognizers ?? [] {
                                if NSStringFromClass(type(of: recognizer)).contains("sSelectionGestureRecognizer") {
                                    recognizer.state = .cancelled
                                }
                            }
                            for subview in view.subviews {
                                cancelGestures(view: subview)
                            }
                        }
                        
                        cancelGestures(view: nativeTabBar)
                    }
                }
                
                guard let item = component.items.first(where: { $0.id == itemWithActiveContextGesture }) else {
                    return
                }
                item.contextAction?(gesture, itemView.contextContainerView)
            }
        }
        
        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard let component = self.component else {
                return
            }
            if let index = tabBar.items?.firstIndex(where: { $0 === item }) {
                if index < component.items.count {
                    component.items[index].action(false)
                }
            }
        }

        private func applyGlassPanPreset() {
            if let glassParametersPan = self.glassParametersPan {
                self.glassView.parameters = glassParametersPan
            }
        }

        private func applyGlassTapPreset() {
            if let glassParametersTap = self.glassParametersTap {
                self.glassView.parameters = glassParametersTap
            }
        }
        
        public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
        
        @objc private func onLongPressGesture(_ recognizer: UILongPressGestureRecognizer) {
            if case .began = recognizer.state {
                if let nativeTabBar = self.nativeTabBar {
                    func cancelGestures(view: UIView) {
                        for recognizer in view.gestureRecognizers ?? [] {
                            if NSStringFromClass(type(of: recognizer)).contains("sSelectionGestureRecognizer") {
                                recognizer.state = .cancelled
                            }
                        }
                        for subview in view.subviews {
                            cancelGestures(view: subview)
                        }
                    }

                    cancelGestures(view: nativeTabBar)
                }
            }
        }

        private func updateGlassPosition(to location: CGPoint, animated: Bool) {
            let minX = self.itemViews.values.compactMap { $0.view?.frame.minX }.min() ?? 0
            let maxX = self.itemViews.values.compactMap { $0.view?.frame.maxX }.max() ?? self.bounds.width
            let glassWidth = self.glassView.frame.width

            var targetX = location.x - glassWidth / 2.0
            targetX = max(minX, min(targetX, maxX - glassWidth))
            let targetFrame = CGRect(origin: CGPoint(x: targetX, y: self.glassView.frame.origin.y), size: self.glassView.frame.size)

            if animated {
                UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
                    self.glassView.frame = targetFrame
                    self.selectionView.frame = targetFrame
                    self.selectedItemsMaskView.frame = targetFrame
                } completion: { [weak self] completed in
                    if !completed {
                        return
                    }
                    guard let self else { return }
                    self.panInitialAnimationCompleted = true
                }
            } else {
                self.glassView.frame = targetFrame
                self.selectionView.frame = targetFrame
                self.selectedItemsMaskView.frame = targetFrame
            }
        }

        @objc private func onPanGesture(_ recognizer: UIPanGestureRecognizer) {
            
            guard let component = self.component, !component.items.isEmpty else {
                return
            }

            switch recognizer.state {
            case .began:
                self.isPanGestureActive = true

                // Cancel any ongoing animations from tap
                self.glassView.layer.removeAllAnimations()
                self.selectionView.layer.removeAllAnimations()
                self.selectedItemsMaskView.layer.removeAllAnimations()
                self.layer.removeAnimation(forKey: "tabBarScale")

                self.applyGlassPanPreset()

                if let selectedId = component.selectedId {
                    self.panStartSelectedIndex = component.items.firstIndex(where: { $0.id == selectedId })
                } else {
                    self.panStartSelectedIndex = nil
                }

                self.panInitialAnimationCompleted = false
                let location = recognizer.location(in: self)
                self.panStartLocation = location

                self.glassView.refreshTexture()
                self.glassView.startLiveAnimating()
                self.glassView.alpha = 1.0
                self.selectionView.alpha = 0.0

                self.glassView.setHighlightScale(1.25, animated: true)
                UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
                    self.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)
                    self.selectionView.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
                    self.selectedItemsMaskView.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
                }

                self.updateGlassPosition(to: location, animated: true)

            case .changed:
                let location = recognizer.location(in: self)
                self.updateGlassPosition(to: location, animated: !self.panInitialAnimationCompleted)

                // Move bar proportionally to pan direction
                let panDelta = location.x - self.panStartLocation.x
                let minX = self.itemViews.values.compactMap { $0.view?.frame.minX }.min() ?? 0
                let maxX = self.itemViews.values.compactMap { $0.view?.frame.maxX }.max() ?? self.bounds.width
                let panRange = maxX - minX
                let normalizedDelta = panRange > 0 ? panDelta / panRange : 0
                let barOffset = max(-self.panBarMaxOffset, min(self.panBarMaxOffset, normalizedDelta * self.panBarMaxOffset))
                self.transform = CGAffineTransform(scaleX: 1.04, y: 1.04).translatedBy(x: barOffset, y: 0)
            
            case .ended, .cancelled:
                guard let startIndex = self.panStartSelectedIndex else {
                    self.isPanGestureActive = false
                    return
                }
                self.panStartSelectedIndex = nil
                self.panInitialAnimationCompleted = false

                let glassCenterX = self.glassView.frame.midX
                var closestIndex = startIndex
                var closestDistance: CGFloat = .greatestFiniteMagnitude

                for (index, item) in component.items.enumerated() {
                    if let itemView = self.itemViews[item.id]?.view {
                        let distance = abs(itemView.frame.midX - glassCenterX)
                        if distance < closestDistance {
                            closestDistance = distance
                            closestIndex = index
                        }
                    }
                }

                self.glassView.setHighlightScale(1.0, animated: true)
                UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
                    self.transform = .identity
                    self.selectionView.transform = .identity
                    self.selectedItemsMaskView.transform = .identity
                }

                if closestIndex != startIndex {
                    // Keep isPanGestureActive true until animation completes to prevent component update interference
                    // Keep skipScalePulse true until animation completes to prevent extra pulse
                    self.skipScalePulse = true
                    component.items[closestIndex].action(false)

                    // Animate glass/selection/mask to new position before fading out
                    if let itemView = self.itemViews[component.items[closestIndex].id]?.view {
                        let targetFrame = CGRect(origin: CGPoint(x: itemView.frame.minX, y: self.glassView.frame.minY), size: self.glassView.frame.size)
                        let direction: Float = targetFrame.origin.x > self.glassView.frame.origin.x ? 1.0 : -1.0
                        self.glassView.animateSpeedPulse(to: direction * 0.3, duration: 0.25)
                        self.glassView.startLiveAnimating()
                        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
                            self.glassView.frame = targetFrame
                            self.selectionView.frame = targetFrame
                            self.selectedItemsMaskView.frame = targetFrame
                        } completion: { [weak self] completed in
                            guard let self, completed else { return }
                            self.isPanGestureActive = false
                            self.skipScalePulse = false
                            UIView.animate(withDuration: 0.15) {
                                self.glassView.alpha = 0.0
                                self.selectionView.alpha = 1.0
                            } completion: { [weak self] completed in
                                guard let self, completed else { return }
                                self.glassView.stopLiveAnimating()
                            }
                        }
                    } else {
                        self.isPanGestureActive = false
                        self.skipScalePulse = false
                        UIView.animate(withDuration: 0.15) {
                            self.glassView.alpha = 0.0
                            self.selectionView.alpha = 1.0
                        } completion: { [weak self] completed in
                            if !completed {
                                return
                            }
                            self?.glassView.stopLiveAnimating()
                        }
                    }
                } else {
                    self.isPanGestureActive = false
                    if let itemView = self.itemViews[component.items[startIndex].id]?.view {
                        let targetFrame = CGRect(origin: CGPoint(x: itemView.frame.minX, y: self.glassView.frame.minY), size: self.glassView.frame.size)
                        let direction: Float = targetFrame.origin.x > self.glassView.frame.origin.x ? 1.0 : -1.0
                        self.glassView.animateSpeedPulse(to: direction * 0.3, duration: 0.3)

                        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
                            self.glassView.frame = targetFrame
                            self.selectionView.frame = targetFrame
                            self.selectedItemsMaskView.frame = targetFrame
                        } completion: { [weak self] completed in
                            guard let self, completed else { return }
                            UIView.animate(withDuration: 0.15) {
                                self.glassView.alpha = 0.0
                                self.selectionView.alpha = 1.0
                            } completion: { [weak self] completed in
                                guard let self, completed else { return }
                                self.glassView.stopLiveAnimating()
                            }
                        }
                    }
                }

            default:
                break
            }
        }

        @objc private func onTapGesture(_ recognizer: UITapGestureRecognizer) {
            guard let component = self.component else {
                return
            }

            switch recognizer.state {
                case .began:
                    self.applyGlassTapPreset()
                case .ended:
                    let point = recognizer.location(in: self)
                    var closestItemView: (AnyHashable, CGFloat)?
                    for (id, itemView) in self.itemViews {
                        guard let itemView = itemView.view else {
                            continue
                        }
                        let distance = abs(point.x - itemView.center.x)
                        if let previousClosestItemView = closestItemView {
                            if previousClosestItemView.1 > distance {
                                closestItemView = (id, distance)
                            }
                        } else {
                            closestItemView = (id, distance)
                        }
                    }
                    
                    if let (id, _) = closestItemView {
                        guard let item = component.items.first(where: { $0.id == id }) else {
                            return
                        }
                        item.action(false)
                        /*if previousSelectedIndex != closestNode.0 {
                        if let selectedIndex = self.selectedIndex, let _ = self.tabBarItems[selectedIndex].item.animationName {
                        container.imageNode.animationNode.play(firstFrame: false, fromIndex: nil)
                        }
                        }*/
                    }
                default:
                break
            }
        }
        
        override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            return super.hitTest(point, with: event)
        } 
        
        public func frameForItem(at index: Int) -> CGRect? {
            guard let component = self.component else {
                return nil
            }
            if index < 0 || index >= component.items.count {
                return nil
            }
            guard let itemView = self.itemViews[component.items[index].id]?.view else {
                return nil
            }
            return self.convert(itemView.bounds, from: itemView)
        }
        
        public override func didMoveToWindow() {
            super.didMoveToWindow()

            self.state?.updated()
        }

        private func animateScalePulse(duration: Double = 0.15, scale: CGFloat = 1.04) {
            let animation = CABasicAnimation(keyPath: "transform.scale")
            animation.fromValue = 1.0
            animation.toValue = scale
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animation.autoreverses = true
            animation.isRemovedOnCompletion = true
            self.layer.add(animation, forKey: "tabBarScale")
        }

        func update(component: TabBarComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            let innerInset: CGFloat = 3.0
            
            let availableSize = CGSize(width: min(500.0, availableSize.width), height: availableSize.height)
            
            let previousComponent = self.component
            self.component = component
            self.state = state
            
            self.overrideUserInterfaceStyle = component.theme.overallDarkAppearance ? .dark : .light
            
            if let nativeTabBar = self.nativeTabBar {
                if previousComponent?.items.map(\.item.title) != component.items.map(\.item.title) {
                    let items: [UITabBarItem] = (0 ..< component.items.count).map { i in
                        return UITabBarItem(title: component.items[i].item.title, image: nil, tag: i)
                    }
                    nativeTabBar.items = items
                    for (_, itemView) in self.itemViews {
                        itemView.view?.removeFromSuperview()
                    }
                    for (_, selectedItemView) in self.selectedItemViews {
                        selectedItemView.view?.removeFromSuperview()
                    }
                    if let index = component.items.firstIndex(where: { $0.id == component.selectedId }) {
                        nativeTabBar.selectedItem = nativeTabBar.items?[index]
                    }
                }
                
                nativeTabBar.frame = CGRect(origin: CGPoint(), size: CGSize(width: availableSize.width, height: component.isTablet ? 74.0 : 83.0))
                nativeTabBar.layoutSubviews()
            }
            
            var nativeItemContainers: [Int: UIView] = [:]
            var nativeSelectedItemContainers: [Int: UIView] = [:]
            if let nativeTabBar = self.nativeTabBar {
                for subview in nativeTabBar.subviews {
                    if NSStringFromClass(type(of: subview)).contains("PlatterView") {
                        for subview in subview.subviews {
                            if NSStringFromClass(type(of: subview)).hasSuffix("SelectedContentView") {
                                for subview in subview.subviews {
                                    if NSStringFromClass(type(of: subview)).hasSuffix("TabButton") {
                                        nativeSelectedItemContainers[nativeSelectedItemContainers.count] = subview
                                    }
                                }
                            } else if NSStringFromClass(type(of: subview)).hasSuffix("ContentView") {
                                for subview in subview.subviews {
                                    if NSStringFromClass(type(of: subview)).hasSuffix("TabButton") {
                                        nativeItemContainers[nativeItemContainers.count] = subview
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            var itemSize = CGSize(width: floor((availableSize.width - innerInset * 2.0) / CGFloat(component.items.count)), height: 56.0)
            itemSize.width = min(94.0, itemSize.width)
            
            if let itemContainer = nativeItemContainers[0] {
                itemSize = itemContainer.bounds.size
            }
            
            let contentHeight = itemSize.height + innerInset * 2.0
            var contentWidth: CGFloat = innerInset
            
            if self.selectionView.image?.size.height != itemSize.height {
                self.selectionView.image = generateStretchableFilledCircleImage(radius: itemSize.height * 0.5, color: .white)?.withRenderingMode(.alwaysTemplate)
            }
            self.selectionView.tintColor = component.theme.list.itemPrimaryTextColor.withMultipliedAlpha(0.05)
            
            var validIds: [AnyHashable] = []
            var selectionFrame: CGRect?
            for index in 0 ..< component.items.count {
                let item = component.items[index]
                validIds.append(item.id)
                
                let itemView: ComponentView<Empty>
                var itemTransition = transition
                
                if let current = self.itemViews[item.id] {
                    itemView = current
                } else {
                    itemTransition = itemTransition.withAnimation(.none)
                    itemView = ComponentView()
                    self.itemViews[item.id] = itemView
                }
                
                let selectedItemView: ComponentView<Empty>
                if let current = self.selectedItemViews[item.id] {
                    selectedItemView = current
                } else {
                    selectedItemView = ComponentView()
                    self.selectedItemViews[item.id] = selectedItemView
                }
                
                let isItemSelected = component.selectedId == item.id
                
                let _ = itemView.update(
                    transition: itemTransition,
                    component: AnyComponent(ItemComponent(
                        item: item,
                        theme: component.theme,
                        isSelected: false
                    )),
                    environment: {},
                    containerSize: itemSize
                )
                let _ = selectedItemView.update(
                    transition: itemTransition,
                    component: AnyComponent(ItemComponent(
                        item: item,
                        theme: component.theme,
                        isSelected: true
                    )),
                    environment: {},
                    containerSize: itemSize
                )
                
                let itemFrame = CGRect(origin: CGPoint(x: contentWidth, y: floor((contentHeight - itemSize.height) * 0.5)), size: itemSize)
                if let itemComponentView = itemView.view as? ItemComponent.View, 
                    let selectedItemComponentView = selectedItemView.view as? ItemComponent.View {

                    if itemComponentView.superview == nil {
                        itemComponentView.isUserInteractionEnabled = false
                        selectedItemComponentView.isUserInteractionEnabled = false
                        
                        if self.nativeTabBar != nil {
                            if let itemContainer = nativeItemContainers[index] {
                                itemContainer.addSubview(itemComponentView)
                            }
                            if let itemContainer = nativeSelectedItemContainers[index] {
                                itemContainer.addSubview(selectedItemComponentView)
                            }
                        } else {
                            self.defaultItemsContainerView.addSubview(itemComponentView)
                            self.selectedItemsContainerView.addSubview(selectedItemComponentView)
                            // self.selectedItemsContainerView.addSubview(selectedItemsMaskView)
                        }
                    }
                    if self.nativeTabBar != nil {
                        if let parentView = itemComponentView.superview {
                            let itemFrame = CGRect(origin: CGPoint(x: floor((parentView.bounds.width - itemSize.width) * 0.5), y: floor((parentView.bounds.height - itemSize.height) * 0.5)), size: itemSize)
                            itemTransition.setFrame(view: itemComponentView, frame: itemFrame)
                            itemTransition.setFrame(view: selectedItemComponentView, frame: itemFrame)
                        }
                    } else {
                        itemTransition.setFrame(view: itemComponentView, frame: itemFrame)
                        itemTransition.setFrame(view: selectedItemComponentView, frame: itemFrame)
                    }
                    
                    if let previousComponent, previousComponent.selectedId != item.id, isItemSelected {
                        itemComponentView.playSelectionAnimation()
                        selectedItemComponentView.playSelectionAnimation()
                    }
                }
                if isItemSelected {
                    selectionFrame = itemFrame
                }
                
                contentWidth += itemFrame.width
            }
            contentWidth += innerInset
            
            var removeIds: [AnyHashable] = []
            for (id, itemView) in self.itemViews {
                if !validIds.contains(id) {
                    removeIds.append(id)
                    itemView.view?.removeFromSuperview()
                    self.selectedItemViews[id]?.view?.removeFromSuperview()
                }
            }
            for id in removeIds {
                self.itemViews.removeValue(forKey: id)
                self.selectedItemViews.removeValue(forKey: id)
            }
            
            if let selectionFrame, self.nativeTabBar == nil {
                var selectionViewTransition = transition
                if self.selectionView.superview == nil {
                    selectionViewTransition = selectionViewTransition.withAnimation(.none)

                    self.backgroundView.contentView.addSubview(self.selectionView)
                    self.itemsContentView.addSubview(self.defaultItemsContainerView)
                    self.itemsContentView.addSubview(self.selectedItemsContainerView)
                    self.addSubview(self.glassView)

                    self.glassView.textureSourceView = self.itemsContentView
                    self.glassView.refreshTexture()

                    self.glassView.alpha = 0.0
                    self.selectionView.alpha = 1.0
                }

                self.glassView.textureFillColor = component.theme.chat.inputPanel.inputBackgroundColor
                selectionViewTransition.setFrame(view: self.selectionView, frame: selectionFrame)

                let glassCornerRadius = Float(selectionFrame.height * 0.5)
                let selectionColor = component.theme.list.itemPrimaryTextColor.withMultipliedAlpha(0.05)
                self.glassParametersTap = GlassPresetsManager.shared.parameters(for: .tabBarGlassTap)
                    .withCornerRadius(glassCornerRadius)
                    .withOverlayColor(selectionColor)
                self.glassParametersPan = GlassPresetsManager.shared.parameters(for: .tabBarGlassPan)
                    .withCornerRadius(glassCornerRadius)
                    .withOverlayColor(selectionColor)
                self.applyGlassTapPreset()

                self.selectedItemsMaskView.layer.cornerRadius = CGFloat(glassCornerRadius)
                self.selectedItemsMaskView.layer.masksToBounds = true
                self.selectedItemsMaskView.frame = selectionFrame

                let selectedId = component.selectedId
                let animationDuration: CFTimeInterval = selectionViewTransition.animation.isImmediate ? 0.0 : 0.4

                if previousComponent != nil && previousComponent?.selectedId != selectedId && !self.isPanGestureActive {
                    if self.skipScalePulse {
                        self.skipScalePulse = false
                    } else {
                        let previousFrame = self.glassView.frame
                        let direction: Float = selectionFrame.midX > previousFrame.midX ? 1.0 : -1.0
                        self.glassView.animateSpeedPulse(to: direction * 0.3, duration: animationDuration)

                        self.glassView.layer.removeAllAnimations()
                        self.selectionView.layer.removeAllAnimations()

                        self.glassView.refreshTexture()
                        self.glassView.startLiveAnimating()

                        self.glassView.alpha = 1.0
                        self.selectionView.alpha = 0.0

                        self.animateScalePulse()
                    }
                }
                if !self.isPanGestureActive {
                    selectionViewTransition.setFrame(view: self.glassView, frame: selectionFrame, completion: { [weak self] _ in
                        guard let self, self.component?.selectedId == selectedId, !self.isPanGestureActive else {
                            return
                        }
                        UIView.animate(withDuration: 0.15) {
                            self.glassView.alpha = 0.0
                            self.selectionView.alpha = 1.0
                        } completion: { [weak self] completed in
                            guard let self, completed, self.component?.selectedId == selectedId, !self.isPanGestureActive else {
                                return
                            }
                            self.glassView.stopLiveAnimating()
                        }
                    })
                }
            } else if self.selectionView.superview != nil {
                self.selectionView.removeFromSuperview()
                self.glassView.removeFromSuperview()
                self.defaultItemsContainerView.removeFromSuperview()
                self.selectedItemsContainerView.removeFromSuperview()
                self.selectedItemsContainerView.removeFromSuperview()
            }

            let size = CGSize(width: min(availableSize.width, contentWidth), height: contentHeight)

            transition.setFrame(view: self.backgroundView, frame: CGRect(origin: CGPoint(), size: size))
           
            self.backgroundView.update(size: size, cornerRadius: size.height * 0.5, isDark: component.theme.overallDarkAppearance, tintColor: .init(kind: .panel, color: component.theme.chat.inputPanel.inputBackgroundColor.withMultipliedAlpha(0.7)), transition: transition)

            if self.nativeTabBar != nil {
                let finalSize = CGSize(width: availableSize.width, height: 62.0)
                transition.setFrame(view: self.contextGestureContainerView, frame: CGRect(origin: CGPoint(), size: finalSize))
                return finalSize
            } else {
                transition.setFrame(view: self.contextGestureContainerView, frame: CGRect(origin: CGPoint(), size: size))
                transition.setFrame(view: self.defaultItemsContainerView, frame: CGRect(origin: CGPoint(), size: size))
                transition.setFrame(view: self.selectedItemsContainerView, frame: CGRect(origin: CGPoint(), size: size))
                transition.setFrame(view: self.itemsContentView, frame: CGRect(origin: CGPoint(), size: size))
                return size
            }
        }
    }
    
    public func makeView() -> View {
        return View(frame: CGRect())
    }
    
    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }

}

private final class ItemComponent: Component {
    let item: TabBarComponent.Item
    let theme: PresentationTheme
    let isSelected: Bool
    
    init(item: TabBarComponent.Item, theme: PresentationTheme, isSelected: Bool) {
        self.item = item
        self.theme = theme
        self.isSelected = isSelected
    }
    
    static func ==(lhs: ItemComponent, rhs: ItemComponent) -> Bool {
        if lhs.item != rhs.item {
            return false
        }
        if lhs.theme !== rhs.theme {
            return false
        }
        if lhs.isSelected != rhs.isSelected {
            return false
        }
        return true
    }
    
    final class View: UIView {
        let contextContainerView: ContextExtractedContentContainingView
        
        private var imageIcon: ComponentView<Empty>?
        private var animationIcon: ComponentView<Empty>?
        private let title = ComponentView<Empty>()
        private var badge: ComponentView<Empty>?
        
        private var component: ItemComponent?
        private weak var state: EmptyComponentState?
        
        private var setImageListener: Int?
        private var setSelectedImageListener: Int?
        private var setBadgeListener: Int?
        
        override init(frame: CGRect) {
            self.contextContainerView = ContextExtractedContentContainingView()
            
            super.init(frame: frame)
            
            self.addSubview(self.contextContainerView)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        deinit {
            if let component = self.component {
                if let setImageListener = self.setImageListener {
                    component.item.item.removeSetImageListener(setImageListener)
                }
                if let setSelectedImageListener = self.setSelectedImageListener {
                    component.item.item.removeSetSelectedImageListener(setSelectedImageListener)
                }
                if let setBadgeListener = self.setBadgeListener {
                    component.item.item.removeSetBadgeListener(setBadgeListener)
                }
            }
        }
        
        func playSelectionAnimation() {
            if let animationIconView = self.animationIcon?.view as? LottieComponent.View {
                animationIconView.playOnce()
            }
        }
        
        func update(component: ItemComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            let previousComponent = self.component
            
            if previousComponent?.item.item !== component.item.item {
                if let setImageListener = self.setImageListener {
                    self.component?.item.item.removeSetImageListener(setImageListener)
                }
                if let setSelectedImageListener = self.setSelectedImageListener {
                    self.component?.item.item.removeSetSelectedImageListener(setSelectedImageListener)
                }
                if let setBadgeListener = self.setBadgeListener {
                    self.component?.item.item.removeSetBadgeListener(setBadgeListener)
                }
                self.setImageListener = component.item.item.addSetImageListener { [weak self] _ in
                    guard let self else {
                        return
                    }
                    self.state?.updated(transition: .immediate, isLocal: true)
                }
                self.setSelectedImageListener = component.item.item.addSetSelectedImageListener { [weak self] _ in
                    guard let self else {
                        return
                    }
                    self.state?.updated(transition: .immediate, isLocal: true)
                }
                self.setBadgeListener = UITabBarItem_addSetBadgeListener(component.item.item) { [weak self] _ in
                    guard let self else {
                        return
                    }
                    self.state?.updated(transition: .immediate, isLocal: true)
                }
            }
            
            self.component = component
            self.state = state
            
            if let animationName = component.item.item.animationName {
                if let imageIcon = self.imageIcon {
                    self.imageIcon = nil
                    imageIcon.view?.removeFromSuperview()
                }
                
                let animationIcon: ComponentView<Empty>
                var iconTransition = transition
                if let current = self.animationIcon {
                    animationIcon = current
                } else {
                    iconTransition = iconTransition.withAnimation(.none)
                    animationIcon = ComponentView()
                    self.animationIcon = animationIcon
                }
                
                let iconSize = animationIcon.update(
                    transition: iconTransition,
                    component: AnyComponent(LottieComponent(
                        content: LottieComponent.AppBundleContent(
                            name: animationName
                        ),
                        color: component.isSelected ? component.theme.rootController.tabBar.selectedTextColor : component.theme.rootController.tabBar.textColor,
                        placeholderColor: nil,
                        startingPosition: .end,
                        size: CGSize(width: 48.0, height: 48.0),
                        loop: false
                    )),
                    environment: {},
                    containerSize: CGSize(width: 48.0, height: 48.0)
                )
                let iconFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - iconSize.width) * 0.5), y: -4.0), size: iconSize).offsetBy(dx: component.item.item.animationOffset.x, dy: component.item.item.animationOffset.y)
                if let animationIconView = animationIcon.view {
                    if animationIconView.superview == nil {
                        if let badgeView = self.badge?.view {
                            self.contextContainerView.contentView.insertSubview(animationIconView, belowSubview: badgeView)
                        } else {
                            self.contextContainerView.contentView.addSubview(animationIconView)
                        }
                    }
                    iconTransition.setFrame(view: animationIconView, frame: iconFrame)
                }
            } else {
                if let animationIcon = self.animationIcon {
                    self.animationIcon = nil
                    animationIcon.view?.removeFromSuperview()
                }
                
                let imageIcon: ComponentView<Empty>
                var iconTransition = transition
                if let current = self.imageIcon {
                    imageIcon = current
                } else {
                    iconTransition = iconTransition.withAnimation(.none)
                    imageIcon = ComponentView()
                    self.imageIcon = imageIcon
                }
                
                let iconSize = imageIcon.update(
                    transition: iconTransition,
                    component: AnyComponent(Image(
                        image: component.isSelected ? component.item.item.selectedImage : component.item.item.image,
                        tintColor: component.isSelected ? component.theme.rootController.tabBar.selectedTextColor : component.theme.rootController.tabBar.textColor,
                        contentMode: .center
                    )),
                    environment: {},
                    containerSize: CGSize(width: 100.0, height: 100.0)
                )
                let iconFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - iconSize.width) * 0.5), y: 3.0), size: iconSize)
                if let imageIconView = imageIcon.view {
                    if imageIconView.superview == nil {
                        if let badgeView = self.badge?.view {
                            self.contextContainerView.contentView.insertSubview(imageIconView, belowSubview: badgeView)
                        } else {
                            self.contextContainerView.contentView.addSubview(imageIconView)
                        }
                    }
                    iconTransition.setFrame(view: imageIconView, frame: iconFrame)
                }
            }
            
            let titleSize = self.title.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: component.item.item.title ?? " ", font: Font.semibold(10.0), textColor: component.isSelected ? component.theme.rootController.tabBar.selectedTextColor : component.theme.rootController.tabBar.textColor))
                )),
                environment: {},
                containerSize: CGSize(width: availableSize.width, height: 100.0)
            )
            let titleFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - titleSize.width) * 0.5), y: availableSize.height - 8.0 - titleSize.height), size: titleSize)
            if let titleView = self.title.view {
                if titleView.superview == nil {
                    self.contextContainerView.contentView.addSubview(titleView)
                }
                titleView.frame = titleFrame
            }
            
            if let badgeText = component.item.item.badgeValue, !badgeText.isEmpty {
                let badge: ComponentView<Empty>
                var badgeTransition = transition
                if let current = self.badge {
                    badge = current
                } else {
                    badgeTransition = badgeTransition.withAnimation(.none)
                    badge = ComponentView()
                    self.badge = badge
                }
                let badgeSize = badge.update(
                    transition: badgeTransition,
                    component: AnyComponent(TextBadgeComponent(
                        text: badgeText,
                        font: Font.regular(13.0),
                        background: component.theme.rootController.tabBar.badgeBackgroundColor,
                        foreground: component.theme.rootController.tabBar.badgeTextColor,
                        insets: UIEdgeInsets(top: 0.0, left: 6.0, bottom: 1.0, right: 6.0)
                    )),
                    environment: {},
                    containerSize: CGSize(width: 100.0, height: 100.0)
                )
                let contentWidth: CGFloat = 25.0
                let badgeFrame = CGRect(origin: CGPoint(x: floor(availableSize.width / 2.0) + contentWidth - badgeSize.width - 1.0, y: 5.0), size: badgeSize)
                if let badgeView = badge.view {
                    if badgeView.superview == nil {
                        self.contextContainerView.contentView.addSubview(badgeView)
                    }
                    badgeTransition.setFrame(view: badgeView, frame: badgeFrame)
                }
            } else if let badge = self.badge {
                self.badge = nil
                badge.view?.removeFromSuperview()
            }
            
            transition.setFrame(view: self.contextContainerView, frame: CGRect(origin: CGPoint(), size: availableSize))
            transition.setFrame(view: self.contextContainerView.contentView, frame: CGRect(origin: CGPoint(), size: availableSize))
            self.contextContainerView.contentRect = CGRect(origin: CGPoint(), size: availableSize)
            
            return availableSize
        }
    }
    
    func makeView() -> View {
        return View(frame: CGRect())
    }
    
    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}
