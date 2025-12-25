import Foundation
import UIKit
import Display
import AsyncDisplayKit
import TelegramPresentationData
import LegacyComponents
import ComponentFlow
import GlassImitation

public final class SliderComponent: Component {
    public final class Discrete: Equatable {
        public let valueCount: Int
        public let value: Int
        public let minValue: Int?
        public let markPositions: Bool
        public let valueUpdated: (Int) -> Void
        
        public init(valueCount: Int, value: Int, minValue: Int? = nil, markPositions: Bool, valueUpdated: @escaping (Int) -> Void) {
            self.valueCount = valueCount
            self.value = value
            self.minValue = minValue
            self.markPositions = markPositions
            self.valueUpdated = valueUpdated
        }
        
        public static func ==(lhs: Discrete, rhs: Discrete) -> Bool {
            if lhs.valueCount != rhs.valueCount {
                return false
            }
            if lhs.value != rhs.value {
                return false
            }
            if lhs.minValue != rhs.minValue {
                return false
            }
            if lhs.markPositions != rhs.markPositions {
                return false
            }
            return true
        }
    }
    
    public final class Continuous: Equatable {
        public let value: CGFloat
        public let minValue: CGFloat?
        public let valueUpdated: (CGFloat) -> Void
        
        public init(value: CGFloat, minValue: CGFloat? = nil, valueUpdated: @escaping (CGFloat) -> Void) {
            self.value = value
            self.minValue = minValue
            self.valueUpdated = valueUpdated
        }
        
        public static func ==(lhs: Continuous, rhs: Continuous) -> Bool {
            if lhs.value != rhs.value {
                return false
            }
            if lhs.minValue != rhs.minValue {
                return false
            }
            return true
        }
    }
    
    public enum Content: Equatable {
        case discrete(Discrete)
        case continuous(Continuous)
    }
    
    public let content: Content
    public let useNative: Bool
    public let trackBackgroundColor: UIColor
    public let trackForegroundColor: UIColor
    public let minTrackForegroundColor: UIColor?
    public let knobSize: CGFloat?
    public let knobColor: UIColor?
    public let isTrackingUpdated: ((Bool) -> Void)?
    
    public init(
        content: Content,
        useNative: Bool = false,
        trackBackgroundColor: UIColor,
        trackForegroundColor: UIColor,
        minTrackForegroundColor: UIColor? = nil,
        knobSize: CGFloat? = nil,
        knobColor: UIColor? = nil,
        isTrackingUpdated: ((Bool) -> Void)? = nil
    ) {
        self.content = content
        self.useNative = useNative
        self.trackBackgroundColor = trackBackgroundColor
        self.trackForegroundColor = trackForegroundColor
        self.minTrackForegroundColor = minTrackForegroundColor
        self.knobSize = knobSize
        self.knobColor = knobColor
        self.isTrackingUpdated = isTrackingUpdated
    }
    
    public static func ==(lhs: SliderComponent, rhs: SliderComponent) -> Bool {
        if lhs.content != rhs.content {
            return false
        }
        if lhs.trackBackgroundColor != rhs.trackBackgroundColor {
            return false
        }
        if lhs.trackForegroundColor != rhs.trackForegroundColor {
            return false
        }
        if lhs.minTrackForegroundColor != rhs.minTrackForegroundColor {
            return false
        }
        if lhs.knobSize != rhs.knobSize {
            return false
        }
        if lhs.knobColor != rhs.knobColor {
            return false
        }
        return true
    }
    
    final class SliderView: UISlider {
        
    }
    
    public final class View: UIView {
        private var nativeSliderView: SliderView?
        private var sliderView: TGPhotoEditorSliderView?

        private var component: SliderComponent?
        private weak var state: EmptyComponentState?

        private var glass: GlassView?
        private let animationTime: Double = 0.3
        private let knobWidthRatio: CGFloat = 1.5
        private var animationWorkItems: [DispatchWorkItem] = []

        private var useGlass: Bool {
            if #available(iOS 26.0, *) {
                return false
            }
            return true
        }

        private func cancelPendingAnimations() {
            animationWorkItems.forEach { $0.cancel() }
            animationWorkItems.removeAll()
        }

        public var hitTestTarget: UIView? {
            return self.sliderView
        }

        override public init(frame: CGRect) {
            super.init(frame: frame)

            if #unavailable(iOS 26.0) {
                let glass = GlassView(preset: .sliderGlass, alwaysLiquid: false)
                glass.isHidden = true
                glass.isUserInteractionEnabled = false
                self.addSubview(glass)
                self.glass = glass
            }
        }

        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        public override func didMoveToSuperview() {
            super.didMoveToSuperview()
            if let superview = superview, let glass = self.glass, glass.textureSourceView == nil {
                glass.textureSourceView = superview
            }
        }

        private func showGlass() {
            guard let glass = self.glass, let sliderView = self.sliderView, let knobView = sliderView.knobView else { return }

            cancelPendingAnimations()

            let scaleUpDuration = 0.12

            let knobHeight = knobView.bounds.height
            let knobSize = CGSize(width: knobHeight * self.knobWidthRatio, height: knobHeight)
            let glassSize = CGSize(width: knobSize.width * 1.02, height: knobSize.height * 1.02)

            let scaleX = knobSize.width / glassSize.width
            let scaleY = knobSize.height / glassSize.height

            glass.bounds = CGRect(origin: .zero, size: glassSize)
            glass.center = self.convert(knobView.center, from: sliderView)
            glass.viewsToHideDuringCapture = [knobView, glass]
            glass.parameters = glass.parameters.withCornerRadius(Float(knobHeight / 2.0))
            self.bringSubviewToFront(glass)

            let currentKnobAlpha = knobView.layer.presentation()?.opacity ?? Float(knobView.alpha)
            let currentKnobTransform = knobView.layer.presentation()?.affineTransform() ?? knobView.transform
            let currentGlassAlpha = glass.layer.presentation()?.opacity ?? Float(glass.alpha)
            let currentGlassTransform = glass.layer.presentation()?.affineTransform() ?? glass.transform

            knobView.layer.removeAllAnimations()
            glass.layer.removeAllAnimations()

            knobView.alpha = CGFloat(currentKnobAlpha)
            knobView.transform = currentKnobTransform

            if glass.isHidden {
                glass.transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
                glass.alpha = 0
                glass.isHidden = false
                glass.refreshTexture()
                glass.startLiveAnimating()
            } else {
                glass.alpha = CGFloat(currentGlassAlpha)
                glass.transform = currentGlassTransform
            }

            UIView.animate(withDuration: scaleUpDuration,
                           delay: 0,
                           options: [.curveEaseOut, .allowUserInteraction]) {
                knobView.alpha = 0
                glass.alpha = 1
                glass.transform = .identity
            }
        }

        private func hideGlass(animated: Bool = true) {
            guard let glass = self.glass, !glass.isHidden else { return }
            guard let sliderView = self.sliderView, let knobView = sliderView.knobView else { return }

            cancelPendingAnimations()

            knobView.layer.removeAllAnimations()
            glass.layer.removeAllAnimations()

            if !animated {
                glass.alpha = 0
                glass.isHidden = true
                glass.stopLiveAnimating()
                glass.transform = .identity
                knobView.alpha = 1
                knobView.transform = .identity
                return
            }

            let currentGlassAlpha = glass.layer.presentation()?.opacity ?? Float(glass.alpha)
            let currentGlassTransform = glass.layer.presentation()?.affineTransform() ?? glass.transform

            glass.alpha = CGFloat(currentGlassAlpha)
            glass.transform = currentGlassTransform

            // Phase 1: Show knob scaled up, start shrinking both glass and knob together
            knobView.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
            knobView.alpha = 1

            UIView.animate(withDuration: 0.15,
                           delay: 0,
                           options: [.curveEaseIn, .allowUserInteraction]) {
                glass.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
                glass.alpha = 0
                knobView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            } completion: { [weak knobView, weak glass] finished in
                guard let glass = glass else { return }

                glass.alpha = 0
                glass.isHidden = true
                glass.stopLiveAnimating()
                glass.transform = .identity

                guard finished, let knobView = knobView else { return }

                // Phase 2: Spring knob back to normal
                UIView.animate(withDuration: 0.2,
                               delay: 0,
                               usingSpringWithDamping: 0.8,
                               initialSpringVelocity: 0.5,
                               options: [.allowUserInteraction]) {
                    knobView.transform = .identity
                }
            }
        }

        private func updateGlassPosition() {
            guard let glass = self.glass, !glass.isHidden, let sliderView = self.sliderView, let knobView = sliderView.knobView else { return }
            glass.center = self.convert(knobView.center, from: sliderView)
        }

        public func cancelGestures() {
            if let sliderView = self.sliderView, let gestureRecognizers = sliderView.gestureRecognizers {
                for gestureRecognizer in gestureRecognizers {
                    gestureRecognizer.isEnabled = false
                    gestureRecognizer.isEnabled = true
                }
            }
        }
        
        func update(component: SliderComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            self.component = component
            self.state = state
            
            let size = CGSize(width: availableSize.width, height: 44.0)
            
            if #available(iOS 26.0, *), component.useNative {
                let sliderView: SliderView
                if let current = self.nativeSliderView {
                    sliderView = current
                } else {
                    sliderView = SliderView()
                    sliderView.disablesInteractiveTransitionGestureRecognizer = true
                    sliderView.addTarget(self, action: #selector(self.sliderValueChanged), for: .valueChanged)
                    sliderView.layer.allowsGroupOpacity = true
                    
                    self.addSubview(sliderView)
                    self.nativeSliderView = sliderView
                    
                    switch component.content {
                    case let .continuous(continuous):
                        sliderView.minimumValue = Float(continuous.minValue ?? 0.0)
                        sliderView.maximumValue = 1.0
                    case let .discrete(discrete):
                        sliderView.minimumValue = 0.0
                        sliderView.maximumValue = Float(discrete.valueCount - 1)
                        sliderView.trackConfiguration = .init(numberOfTicks: discrete.valueCount)
                    }
                }
                switch component.content {
                case let .continuous(continuous):
                    sliderView.value = Float(continuous.value)
                case let .discrete(discrete):
                    sliderView.value = Float(discrete.value)
                }
                sliderView.minimumTrackTintColor = component.trackForegroundColor
                sliderView.maximumTrackTintColor = component.trackBackgroundColor
                
                transition.setFrame(view: sliderView, frame: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: availableSize.width, height: 44.0)))
            } else {
                let isTrackingUpdated = component.isTrackingUpdated

                let sliderView: TGPhotoEditorSliderView
                if let current = self.sliderView {
                    sliderView = current
                } else {
                    sliderView = TGPhotoEditorSliderView()
                    sliderView.enablePanHandling = true
                    if let knobSize = component.knobSize {
                        sliderView.lineSize = knobSize + 4.0
                    } else {
                        sliderView.lineSize = 4.0
                    }
                    sliderView.trackCornerRadius = sliderView.lineSize * 0.5
                    sliderView.dotSize = 5.0
                    sliderView.minimumValue = 0.0
                    sliderView.startValue = 0.0
                    sliderView.disablesInteractiveTransitionGestureRecognizer = true
                    
                    switch component.content {
                    case let .discrete(discrete):
                        sliderView.maximumValue = CGFloat(discrete.valueCount - 1)
                        sliderView.positionsCount = discrete.valueCount
                        sliderView.useLinesForPositions = true
                        sliderView.markPositions = discrete.markPositions
                    case .continuous:
                        sliderView.maximumValue = 1.0
                    }
                    
                    sliderView.backgroundColor = nil
                    sliderView.isOpaque = false
                    sliderView.backColor = component.trackBackgroundColor
                    sliderView.startColor = component.trackBackgroundColor
                    sliderView.trackColor = component.trackForegroundColor
                    if let knobSize = component.knobSize {
                        let knobWidth = knobSize * 1.3
                        let cornerRadius = knobSize / 2.0
                        sliderView.knobImage = generateImage(CGSize(width: knobWidth + 12.0, height: knobSize + 12.0), rotatedContext: { size, context in
                            context.clear(CGRect(origin: CGPoint(), size: size))
                            context.setShadow(offset: CGSize(width: 0.0, height: -3.0), blur: 12.0, color: UIColor(white: 0.0, alpha: 0.25).cgColor)
                            if let knobColor = component.knobColor {
                                context.setFillColor(knobColor.cgColor)
                            } else {
                                context.setFillColor(UIColor.white.cgColor)
                            }
                            let path = UIBezierPath(roundedRect: CGRect(origin: CGPoint(x: 6.0, y: 6.0), size: CGSize(width: knobWidth, height: knobSize)), cornerRadius: cornerRadius)
                            context.addPath(path.cgPath)
                            context.fillPath()
                        })
                    } else {
                        let knobHeight: CGFloat = 22.0
                        let knobWidth: CGFloat = knobHeight * self.knobWidthRatio
                        let cornerRadius = knobHeight / 2.0
                        sliderView.knobImage = generateImage(CGSize(width: knobWidth + 12.0, height: knobHeight + 12.0),
                                                             rotatedContext: { size, context in
                            context.clear(CGRect(origin: CGPoint(), size: size))
                            context.setShadow(offset: CGSize(width: 0.0, height: -3.0), blur: 12.0, color: UIColor(white: 0.0, alpha: 0.25).cgColor)
                            context.setFillColor(UIColor.white.cgColor)
                            let path = UIBezierPath(roundedRect: CGRect(origin: CGPoint(x: 6.0, y: 6.0 + 1.0), size: CGSize(width: knobWidth, height: knobHeight)), cornerRadius: cornerRadius)
                            context.addPath(path.cgPath)
                            context.fillPath()
                        })
                    }
                    
                    sliderView.frame = CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: size)
                    sliderView.hitTestEdgeInsets = UIEdgeInsets(top: -sliderView.frame.minX, left: 0.0, bottom: 0.0, right: -sliderView.frame.minX)
                    
                    
                    sliderView.disablesInteractiveTransitionGestureRecognizer = true
                    sliderView.addTarget(self, action: #selector(self.sliderValueChanged), for: .valueChanged)
                    sliderView.layer.allowsGroupOpacity = true
                    self.sliderView = sliderView
                    self.addSubview(sliderView)
                }
                sliderView.lowerBoundTrackColor = component.minTrackForegroundColor
                switch component.content {
                case let .discrete(discrete):
                    sliderView.value = CGFloat(discrete.value)
                    if let minValue = discrete.minValue {
                        sliderView.lowerBoundValue = CGFloat(minValue)
                    } else {
                        sliderView.lowerBoundValue = 0.0
                    }
                case let .continuous(continuous):
                    sliderView.value = continuous.value
                    if let minValue = continuous.minValue {
                        sliderView.lowerBoundValue = minValue
                    } else {
                        sliderView.lowerBoundValue = 0.0
                    }
                }
                sliderView.interactionBegan = { [weak self] in
                    self?.showGlass()
                    isTrackingUpdated?(true)
                }
                sliderView.interactionEnded = { [weak self] in
                    self?.hideGlass()
                    isTrackingUpdated?(false)
                }
                
                let sliderInset: CGFloat = 10.0 //hack for the size due to discrepancy in ios stuff
                transition.setFrame(view: sliderView, frame: CGRect(origin: CGPoint(x: sliderInset, y: 0.0), size: CGSize(width: availableSize.width - sliderInset * 2.0, height: 44.0)))
                sliderView.hitTestEdgeInsets = UIEdgeInsets(top: 0.0, left: -sliderInset, bottom: 0.0, right: -sliderInset)
            }
            
            return size
        }
        
        @objc private func sliderValueChanged() {
            self.updateGlassPosition()

            guard let component = self.component else {
                return
            }
            let floatValue: CGFloat
            if let sliderView = self.sliderView {
                floatValue = sliderView.value
            } else if let nativeSliderView = self.nativeSliderView {
                floatValue = CGFloat(nativeSliderView.value)
            } else {
                return
            }
            switch component.content {
            case let .discrete(discrete):
                discrete.valueUpdated(Int(floatValue))
            case let .continuous(continuous):
                continuous.valueUpdated(floatValue)
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
