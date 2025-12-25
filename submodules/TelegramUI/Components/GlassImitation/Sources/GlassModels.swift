//
//  GlassView.swift
//  GlassImitation
//
//  Created by iN 
//

import Foundation
import UIKit
import Metal
import MetalKit


//to work with familiar types on the client side (for non-presets)
public struct GlassParameters {
    let glassCenter: CGPoint
    let cornerRadius: Float
    let refraction: Float
    let edgeThickness: Float
    let edgeBlur: Float
    let chromaticStrength: Float
    let overlayColor: UIColor
    let contentBlur: Float
    let distortionExponent: Float
    let distortionDamping: Float
    let chromaticExponent: Float
    let innerShadowBlur: Float
    let innerShadowOpacity: Float
    let innerShadowColor: UIColor
    let innerShadowTopGradient: Float
    let borderWidth: Float
    let borderColor: UIColor
    let borderRefraction: Float

    public init(glassCenter: CGPoint,
                cornerRadius: Float,
                refraction: Float,
                edgeThickness: Float,
                edgeBlur: Float,
                chromaticStrength: Float,
                overlayColor: UIColor,
                contentBlur: Float,
                distortionExponent: Float,
                distortionDamping: Float,
                chromaticExponent: Float,
                innerShadowBlur: Float,
                innerShadowOpacity: Float,
                innerShadowColor: UIColor,
                innerShadowTopGradient: Float,
                borderWidth: Float,
                borderColor: UIColor,
                borderRefraction: Float) {
        self.glassCenter = glassCenter
        self.cornerRadius = cornerRadius
        self.refraction = refraction
        self.edgeThickness = edgeThickness
        self.edgeBlur = edgeBlur
        self.chromaticStrength = chromaticStrength
        self.overlayColor = overlayColor
        self.contentBlur = contentBlur
        self.distortionExponent = distortionExponent
        self.distortionDamping = distortionDamping
        self.chromaticExponent = chromaticExponent
        self.innerShadowBlur = innerShadowBlur
        self.innerShadowOpacity = innerShadowOpacity
        self.innerShadowColor = innerShadowColor
        self.innerShadowTopGradient = innerShadowTopGradient
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.borderRefraction = borderRefraction
    }

    public func withCornerRadius(_ cornerRadius: Float) -> GlassParameters {
        return GlassParameters(
            glassCenter: glassCenter,
            cornerRadius: cornerRadius,
            refraction: refraction,
            edgeThickness: edgeThickness,
            edgeBlur: edgeBlur,
            chromaticStrength: chromaticStrength,
            overlayColor: overlayColor,
            contentBlur: contentBlur,
            distortionExponent: distortionExponent,
            distortionDamping: distortionDamping,
            chromaticExponent: chromaticExponent,
            innerShadowBlur: innerShadowBlur,
            innerShadowOpacity: innerShadowOpacity,
            innerShadowColor: innerShadowColor,
            innerShadowTopGradient: innerShadowTopGradient,
            borderWidth: borderWidth,
            borderColor: borderColor,
            borderRefraction: borderRefraction
        )
    }

    public func withOverlayColor(_ overlayColor: UIColor) -> GlassParameters {
        return GlassParameters(
            glassCenter: glassCenter,
            cornerRadius: cornerRadius,
            refraction: refraction,
            edgeThickness: edgeThickness,
            edgeBlur: edgeBlur,
            chromaticStrength: chromaticStrength,
            overlayColor: overlayColor,
            contentBlur: contentBlur,
            distortionExponent: distortionExponent,
            distortionDamping: distortionDamping,
            chromaticExponent: chromaticExponent,
            innerShadowBlur: innerShadowBlur,
            innerShadowOpacity: innerShadowOpacity,
            innerShadowColor: innerShadowColor,
            innerShadowTopGradient: innerShadowTopGradient,
            borderWidth: borderWidth,
            borderColor: borderColor,
            borderRefraction: borderRefraction
        )
    }
}

public struct GlassInstance {
    var position: SIMD2<Float>  // Top-left 
    var size: SIMD2<Float>
    var cornerRadius: Float

    public init(position: SIMD2<Float>, size: SIMD2<Float>, cornerRadius: Float) {
        self.position = position
        self.size = size
        self.cornerRadius = cornerRadius
    }
}

public struct GlassViewSettings {
    var liveAnimationUpdateFrequency: Int // Update every N frames
    var liveAnimationCaptureScale: CGFloat // Scale for capture texture
    var sdfBlendAmount: Float
    var expansion: Float // Extra padding around view for scale/effects
    var speedSpringStiffness: Float
    var speedSpringDamping: Float

    public init(liveAnimationUpdateFrequency: Int, 
                liveAnimationCaptureScale: CGFloat, 
                sdfBlendAmount: Float, 
                expansion: Float, 
                speedSpringStiffness: Float, 
                speedSpringDamping: Float) {
        self.liveAnimationUpdateFrequency = liveAnimationUpdateFrequency
        self.liveAnimationCaptureScale = liveAnimationCaptureScale
        self.sdfBlendAmount = sdfBlendAmount
        self.expansion = expansion
        self.speedSpringStiffness = speedSpringStiffness
        self.speedSpringDamping = speedSpringDamping
    }
}

public struct GlassUniforms {
    var size: SIMD2<Float>
    var glassCenter: SIMD2<Float>
    var cornerRadius: Float
    var refraction: Float
    var edgeThickness: Float
    var edgeBlur: Float
    var chromaticStrength: Float
    var overlayColor: SIMD4<Float>
    var instanceCount: Int32
    var sdfBlendAmount: Float
    var speed: Float
    var contentBlur: Float
    var highlightScale: Float
    var distortionExponent: Float
    var distortionDamping: Float
    var chromaticExponent: Float
    var innerShadowBlur: Float
    var innerShadowOpacity: Float
    var innerShadowTopGradient: Float
    var borderWidth: Float
    var borderRefraction: Float
    var _padding: Float = 0
    var innerShadowColor: SIMD4<Float>
    var borderColor: SIMD4<Float>

    init(size: SIMD2<Float>,
         parameters: GlassParameters,
         instanceCount: Int,
         sdfBlendAmount: Float,
         speed: Float,
         highlightScale: Float) {
        self.size = size
        self.glassCenter = SIMD2<Float>(Float(parameters.glassCenter.x), Float(parameters.glassCenter.y))
        self.cornerRadius = parameters.cornerRadius
        self.refraction = parameters.refraction
        self.edgeThickness = parameters.edgeThickness
        self.edgeBlur = parameters.edgeBlur
        self.chromaticStrength = parameters.chromaticStrength
        self.instanceCount = Int32(instanceCount)
        self.sdfBlendAmount = sdfBlendAmount
        self.speed = speed
        self.contentBlur = parameters.contentBlur
        self.highlightScale = highlightScale
        self.distortionExponent = parameters.distortionExponent
        self.distortionDamping = parameters.distortionDamping
        self.chromaticExponent = parameters.chromaticExponent
        self.innerShadowBlur = parameters.innerShadowBlur
        self.innerShadowOpacity = parameters.innerShadowOpacity
        self.innerShadowTopGradient = parameters.innerShadowTopGradient
        self.borderWidth = parameters.borderWidth
        self.borderRefraction = parameters.borderRefraction

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        parameters.overlayColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.overlayColor = SIMD4<Float>(Float(r), Float(g), Float(b), Float(a))

        var ir: CGFloat = 0, ig: CGFloat = 0, ib: CGFloat = 0, ia: CGFloat = 0
        parameters.innerShadowColor.getRed(&ir, green: &ig, blue: &ib, alpha: &ia)
        self.innerShadowColor = SIMD4<Float>(Float(ir), Float(ig), Float(ib), Float(ia))

        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        parameters.borderColor.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        self.borderColor = SIMD4<Float>(Float(br), Float(bg), Float(bb), Float(ba))
    }
}