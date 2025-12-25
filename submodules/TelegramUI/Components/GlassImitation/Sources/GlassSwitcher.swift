 //
//  GlassSwitcher.swift
//  GlassImitation
//
//  Created by iN

import Foundation
import UIKit

public final class GlassSwitcher : UISwitch {
    
    private let animationTime = 0.3
    private let offset: CGPoint // a bit hacky, but need to align fast. Due to the Switch's size discrepancy in different iOS versions

    private var _onTintColor: UIColor = .systemBlue
    private var _offTintColor: UIColor = .systemGray4
    private var _thumbTintColor: UIColor = .white
    
    public let glass = GlassView(preset: .switcherGlass, alwaysLiquid: false)
    private let customThumb = UIView()
    private let customTrack = UIView()
    
    private let trackHeight: CGFloat = 28
    private let trackWidth: CGFloat = 63
    private var thumbWidth: CGFloat { trackWidth / 2 + 6 }
    private var thumbHeight: CGFloat { trackHeight - 4 }
    private let thumbPadding: CGFloat = 3
    private var glassWidth: CGFloat { thumbWidth + 18 }
    private var glassHeight: CGFloat { thumbHeight + 12 }
    
    private var panGesture: UIPanGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!
    
    override public var onTintColor: UIColor? {
        get { _onTintColor }
        set {
            _onTintColor = newValue ?? .systemBlue
            updateTrackColor()
        }
    }
    
    override public var tintColor: UIColor! {
        get { _offTintColor }
        set {
            _offTintColor = newValue ?? .systemGray4
            updateTrackColor()
        }
    }
    
    override public var thumbTintColor: UIColor? {
        get { _thumbTintColor }
        set {
            _thumbTintColor = newValue ?? .white
            customThumb.backgroundColor = _thumbTintColor
        }
    }
    
    override public var backgroundColor: UIColor? {
        get { customTrack.backgroundColor }
        set {
            _offTintColor = newValue ?? .systemGray4
            updateTrackColor()
        }
    }

    private lazy var thumbCenterX: CGFloat = minCenterX {
        didSet { updateThumbRelatedCenters() }
    }


    //MARK: - System -

    public init(frame: CGRect = .zero, offset: CGPoint = .zero) {
        self.offset = offset
        super.init(frame: CGRect(origin: frame.origin, size: CGSize(width: trackWidth, height: trackHeight)))
        
        removeDefaultUI()
        
        setupUI()
        setupGestures()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let trackBounds = CGRect(x: offset.x, y: offset.y, width: trackWidth, height: trackHeight)
        return trackBounds.contains(point)
    }

    override public func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview != nil && glass.textureSourceView == nil {
            glass.textureSourceView = superview
        }
    }

    private func removeDefaultUI() {
        subviews.forEach { $0.removeFromSuperview() }
        gestureRecognizers?.forEach { removeGestureRecognizer($0) }
        for subview in subviews {
            if subview !== customTrack && subview !== customThumb && subview !== glass {
                subview.removeFromSuperview()
            }
        }
    }
    
    override public func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        return false
    }


    //MARK: - UI -
    
    private func setupUI() {
        clipsToBounds = false

        customTrack.frame = CGRect(x: offset.x, y: offset.y, width: trackWidth, height: trackHeight)
        customTrack.backgroundColor = _offTintColor
        customTrack.layer.cornerRadius = trackHeight / 2
        addSubview(customTrack)
        
        customThumb.bounds = CGRect(x: 0, y: 0, width: thumbWidth, height: thumbHeight)
        customThumb.center = CGPoint(x: thumbCenterX, y: offset.y + trackHeight / 2)
        customThumb.backgroundColor = _thumbTintColor
        glass.isUserInteractionEnabled = false
        customThumb.layer.cornerRadius = thumbHeight / 2
        addSubview(customThumb)

        glass.bounds = CGRect(x: 0, y: 0, width: glassWidth, height: glassHeight)
        glass.center = CGPoint(x: thumbCenterX, y: offset.y + trackHeight / 2)
        glass.isHidden = true
        glass.isUserInteractionEnabled = false
        glass.viewsToHideDuringCapture = [customThumb, customTrack]
        glass.viewsToUnhideDuringCapture = [customThumb]
        addSubview(glass)
    }

    private func setupGestures() {
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(panGesture)
        tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)
    }
    
    private func updateThumbRelatedCenters() {
        customThumb.center = CGPoint(x: thumbCenterX, y: offset.y + trackHeight / 2)
        glass.center = CGPoint(x: thumbCenterX, y: offset.y + trackHeight / 2)
    }

    private func updateTrackColor() {
        customTrack.backgroundColor = isOn ? _onTintColor : _offTintColor
    }


    //MARK: - Animations -
    
    private func showGlass() {
        updateThumbRelatedCenters()

        let currentThumbAlpha = customThumb.layer.presentation()?.opacity ?? Float(customThumb.alpha)
        let currentThumbTransform = customThumb.layer.presentation()?.affineTransform() ?? customThumb.transform
        let currentGlassAlpha = glass.layer.presentation()?.opacity ?? Float(glass.alpha)
        let currentGlassTransform = glass.layer.presentation()?.affineTransform() ?? glass.transform

        customThumb.layer.removeAllAnimations()
        glass.layer.removeAllAnimations()

        customThumb.alpha = CGFloat(currentThumbAlpha)
        customThumb.transform = currentThumbTransform

        if glass.isHidden {
            let scaleX = thumbWidth / glassWidth
            let scaleY = thumbHeight / glassHeight
            glass.transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
            glass.alpha = 0
            glass.isHidden = false
            glass.refreshTexture()
            glass.startLiveAnimating()
        } else {
            glass.alpha = CGFloat(currentGlassAlpha)
            glass.transform = currentGlassTransform
        }
        
        UIView.animate(withDuration: animationTime,
                       delay: 0,
                       options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]) {
            self.customThumb.alpha = 0
            self.customThumb.transform = .identity
            self.glass.alpha = 1
            self.glass.transform = .identity
        }
    }
    
    private func hideGlass() {
        if glass.isHidden { return }
        
        let currentGlassAlpha = glass.layer.presentation()?.opacity ?? Float(glass.alpha)
        let currentGlassTransform = glass.layer.presentation()?.affineTransform() ?? glass.transform
        
        customThumb.layer.removeAllAnimations()
        glass.layer.removeAllAnimations()
        
        glass.alpha = CGFloat(currentGlassAlpha)
        glass.transform = currentGlassTransform
        
        let scaleX = thumbWidth / glassWidth
        let scaleY = thumbHeight / glassHeight
        
        UIView.animate(withDuration: 0.15,
                       delay: 0,
                       options: [.curveEaseIn, .beginFromCurrentState, .allowUserInteraction]) {
            self.glass.transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
        } completion: { finished in
            guard finished else { return }

            self.glass.alpha = 0
            self.glass.isHidden = true
            self.glass.stopLiveAnimating()
            self.glass.transform = .identity
            
            self.customThumb.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
            self.customThumb.alpha = 1
            
            UIView.animate(withDuration: 0.25,
                           delay: 0,
                           usingSpringWithDamping: 0.6,
                           initialSpringVelocity: 0.8,
                           options: [.allowUserInteraction]) {
                self.customThumb.transform = .identity
            }
        }
    }
    

    // MARK: - Gestures -

    private var minCenterX: CGFloat { offset.x + thumbPadding + thumbWidth / 2 }
    private var maxCenterX: CGFloat { offset.x + trackWidth - thumbPadding - thumbWidth / 2 }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        
        switch gesture.state {
        case .began:
            showGlass()
        case .changed:
            let baseX = isOn ? maxCenterX : minCenterX
            thumbCenterX = min(max(baseX + translation.x, minCenterX), maxCenterX)
            let progress = (thumbCenterX - minCenterX) / (maxCenterX - minCenterX)
            customTrack.backgroundColor = interpolateColor(from: _offTintColor, to: _onTintColor, progress: progress)
        case .ended, .cancelled:
            let shouldBeOn = thumbCenterX > (minCenterX + maxCenterX) / 2
            finishPanWithSequence(to: shouldBeOn)
        default:
            break
        }
    }
    
    private func interpolateColor(from: UIColor, to: UIColor, progress: CGFloat) -> UIColor {
        var fromR: CGFloat = 0, fromG: CGFloat = 0, fromB: CGFloat = 0, fromA: CGFloat = 0
        var toR: CGFloat = 0, toG: CGFloat = 0, toB: CGFloat = 0, toA: CGFloat = 0
        from.getRed(&fromR, green: &fromG, blue: &fromB, alpha: &fromA)
        to.getRed(&toR, green: &toG, blue: &toB, alpha: &toA)
        
        let p = min(max(progress, 0), 1)
        return UIColor(
            red: fromR + (toR - fromR) * p,
            green: fromG + (toG - fromG) * p,
            blue: fromB + (toB - fromB) * p,
            alpha: fromA + (toA - fromA) * p
        )
    }
    

    // MARK: - Gesture -


    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
       animateWithSequence(to: !isOn)
    }

    private func finishPanWithSequence(to on: Bool) {
        cancelPendingAnimations()

        let moveDuration = animationTime
        let scaleDownDuration = 0.15
        let scaleDownDelay = moveDuration * 0.5  // overlap

        super.setOn(on, animated: false)
        let targetX = on ? maxCenterX : minCenterX

        let scaleX = thumbWidth / glassWidth
        let scaleY = thumbHeight / glassHeight

        UIView.animate(withDuration: moveDuration,
                       delay: 0,
                       options: [.curveEaseOut, .allowUserInteraction]) {
            self.thumbCenterX = targetX
            self.customTrack.backgroundColor = on ? self._onTintColor : self._offTintColor
        }

        sendActions(for: .valueChanged)

        let scaleDownWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            UIView.animate(withDuration: scaleDownDuration,
                           delay: 0,
                           options: [.curveEaseIn, .allowUserInteraction]) {
                self.glass.transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
            } completion: { finished in
                guard finished else { return }

                self.glass.alpha = 0
                self.glass.isHidden = true
                self.glass.stopLiveAnimating()
                self.glass.transform = .identity

                self.customThumb.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
                self.customThumb.alpha = 1

                UIView.animate(withDuration: 0.2,
                               delay: 0,
                               usingSpringWithDamping: 0.7,
                               initialSpringVelocity: 0.5,
                               options: [.allowUserInteraction]) {
                    self.customThumb.transform = .identity
                }
            }
        }
        animationWorkItems.append(scaleDownWorkItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + scaleDownDelay, execute: scaleDownWorkItem)
    }

    private var animationWorkItems: [DispatchWorkItem] = []

    private func cancelPendingAnimations() {
        animationWorkItems.forEach { $0.cancel() }
        animationWorkItems.removeAll()
    }

    private func animateWithSequence(to on: Bool) {
        cancelPendingAnimations()

        let scaleUpDuration = 0.12
        let moveDuration = animationTime
        let scaleDownDuration = 0.15
        let moveDelay = 0.06  // overlap: start moving before scale-up finishes
        let scaleDownDelay = moveDuration * 0.6  // overlap: start shrinking before move finishes

        let scaleX = thumbWidth / glassWidth
        let scaleY = thumbHeight / glassHeight

        let currentThumbX = customThumb.layer.presentation()?.position.x ?? customThumb.center.x
        let currentGlassTransform = glass.layer.presentation()?.affineTransform() ?? glass.transform
        let currentGlassAlpha = glass.layer.presentation()?.opacity ?? Float(glass.alpha)

        customThumb.layer.removeAllAnimations()
        glass.layer.removeAllAnimations()
        thumbCenterX = currentThumbX

        if glass.isHidden {
            glass.transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
            glass.alpha = 0
            glass.isHidden = false
            glass.refreshTexture()
            glass.startLiveAnimating()
        } else {
            glass.transform = currentGlassTransform
            glass.alpha = CGFloat(currentGlassAlpha)
        }

        // Phase 1: Increase size (scale up)
        UIView.animate(withDuration: scaleUpDuration,
                       delay: 0,
                       options: [.curveEaseOut, .allowUserInteraction]) {
            self.customThumb.alpha = 0
            self.glass.alpha = 1
            self.glass.transform = .identity
        }

        // Set state immediately (before delayed work items)
        super.setOn(on, animated: false)

        // Phase 2: Move (starts with overlap)
        let moveWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let targetX = on ? self.maxCenterX : self.minCenterX

            UIView.animate(withDuration: moveDuration,
                           delay: 0,
                           options: [.curveEaseInOut, .allowUserInteraction]) {
                self.thumbCenterX = targetX
                self.customTrack.backgroundColor = on ? self._onTintColor : self._offTintColor
            }

            self.sendActions(for: .valueChanged)
        }
        animationWorkItems.append(moveWorkItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + moveDelay, execute: moveWorkItem)

        // Phase 3: Decrease size (starts with overlap, before move finishes)
        let scaleDownWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            UIView.animate(withDuration: scaleDownDuration,
                           delay: 0,
                           options: [.curveEaseIn, .allowUserInteraction]) {
                self.glass.transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
            } completion: { finished in
                guard finished else { return }

                self.glass.alpha = 0
                self.glass.isHidden = true
                self.glass.stopLiveAnimating()
                self.glass.transform = .identity

                self.customThumb.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
                self.customThumb.alpha = 1

                UIView.animate(withDuration: 0.2,
                               delay: 0,
                               usingSpringWithDamping: 0.7,
                               initialSpringVelocity: 0.5,
                               options: [.allowUserInteraction]) {
                    self.customThumb.transform = .identity
                }
            }
        }
        animationWorkItems.append(scaleDownWorkItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + moveDelay + scaleDownDelay, execute: scaleDownWorkItem)
    }

    override public func setOn(_ on: Bool, animated: Bool) {
        setOn(on, animated: animated, sendActions: false, completion: nil)
    }

    public func setOn(_ on: Bool, animated: Bool, sendActions: Bool = false, completion: (() -> Void)?) {
        super.setOn(on, animated: false)
        
        let targetX = on ? maxCenterX : minCenterX

        if animated {
            let currentX = customThumb.layer.presentation()?.position.x ?? customThumb.center.x
            customThumb.layer.removeAllAnimations()
            thumbCenterX = currentX

            UIView.animate(withDuration: animationTime, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
                self.thumbCenterX = targetX
                self.customTrack.backgroundColor = on ? self._onTintColor : self._offTintColor
            } completion: { finished in
                if finished {
                    completion?()
                }
            }
        } else {
            thumbCenterX = targetX
            customTrack.backgroundColor = on ? _onTintColor : _offTintColor
            completion?()
        }

        if sendActions {
            self.sendActions(for: .valueChanged)
        }
    }
    
    override public var intrinsicContentSize: CGSize {
        CGSize(width: trackWidth, height: trackHeight)
    }
}