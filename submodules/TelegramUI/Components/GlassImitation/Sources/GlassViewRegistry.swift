//
//  GlassViewRegistry.swift
//  GlassImitation
//
//  Created by iN
//

import Foundation
import UIKit
import Metal
import MetalKit

//for sdf - to let glasses know about each other and merge 

public final class GlassViewRegistry {
    private weak var parentView: UIView?
    private var glassViews: [WeakGlassView] = [] //may rework on Set for O(1) lookup, but i don't feel like there will be too many glass views in one parent
    
    private struct WeakGlassView {
        weak var view: GlassView?
    }
    
    public init(parentView: UIView) {
        self.parentView = parentView
    }
    
    public func register(_ glassView: GlassView) {
        if !glassViews.contains(where: { $0.view === glassView }) {
            glassViews.append(WeakGlassView(view: glassView))
        }
        glassViews = glassViews.filter { $0.view != nil }
    }
    
    public func unregister(_ glassView: GlassView) {
        glassViews.removeAll { $0.view === glassView }
    }
    
    public func getInstances(for glassView: GlassView, expansion: Float) -> [GlassInstance] {
        glassViews = glassViews.filter { $0.view != nil }

        let expansion = CGFloat(expansion)

        var result: [GlassInstance] = []

        // First add self
        let selfInstance = GlassInstance(
            position: SIMD2<Float>(Float(expansion), Float(expansion)),
            size: SIMD2<Float>(Float(glassView.bounds.width), Float(glassView.bounds.height)),
            cornerRadius: glassView.parameters.cornerRadius
        )
        result.append(selfInstance)

        let selfCenter = glassView.superview?.convert(glassView.center, to: nil) ?? .zero
        let selfSize = glassView.bounds.size

        for weakView in glassViews {
            //sanity checks
            guard let view = weakView.view, view !== glassView else { continue }
            guard !view.isHidden else { continue }
            if let parent = view.superview, parent.isHidden { continue }
            guard view.participatesInMerge else { continue }
            guard view.bounds.width > 0 && view.bounds.height > 0 else { continue }

            let otherCenter = view.superview?.convert(view.center, to: nil) ?? .zero

            let otherScale = CGFloat(view.highlightScale)
            let otherSize = CGSize(width: view.bounds.width * otherScale, height: view.bounds.height * otherScale)

            // Calculate top-left positions from centers
            let selfTopLeft = CGPoint(x: selfCenter.x - selfSize.width / 2, y: selfCenter.y - selfSize.height / 2)
            let otherTopLeft = CGPoint(x: otherCenter.x - otherSize.width / 2, y: otherCenter.y - otherSize.height / 2)

            // Calculate relative position
            let relativeX = otherTopLeft.x - selfTopLeft.x + expansion
            let relativeY = otherTopLeft.y - selfTopLeft.y + expansion

            let expandedHeight = glassView.bounds.height + expansion * 2
            let flippedY = expandedHeight - relativeY - otherSize.height

            result.append(GlassInstance(
                position: SIMD2<Float>(Float(relativeX), Float(flippedY)),
                size: SIMD2<Float>(Float(otherSize.width), Float(otherSize.height)),
                cornerRadius: view.parameters.cornerRadius * Float(otherScale)
            ))
        }

        return result
    }
    
    public func notifyAll() {
        glassViews.forEach { weakView in
            weakView.view?.refreshTexture()
        }
    }
    
    public func getAllViews() -> [GlassView] {
        glassViews.compactMap { $0.view }
    }
}
