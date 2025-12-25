//
//  GlassPresets.swift
//  GlassImitation
//
//  Created by iN 
//


import Foundation
import UIKit

//to tune parameters (via GlassPresets.json) with no rebuilds every time or i will go mad

public enum GlassPreset: String {
    case tabBarGlassTap
    case tabBarGlassPan
    case panelGlass
    case sliderGlass
    case switcherGlass
}

public final class GlassPresetsManager {
    public static let shared = GlassPresetsManager()

    private var presets: [String: PresetData] = [:]

    private struct PresetData: Codable {
        let cornerRadius: Float
        let refraction: Float
        let edgeThickness: Float
        let edgeBlur: Float
        let chromaticStrength: Float
        let overlayColorHex: String
        let contentBlur: Float
        let sdfBlendAmount: Float
        let expansion: Float
        let distortionExponent: Float
        let distortionDamping: Float
        let chromaticExponent: Float
        let innerShadowBlur: Float
        let innerShadowOpacity: Float
        let innerShadowColorHex: String
        let innerShadowTopGradient: Float
        let borderWidth: Float
        let borderColorHex: String
        let borderRefraction: Float
        let liveAnimationUpdateFrequency: Int
        let liveAnimationCaptureScale: Float
        let speedSpringStiffness: Float
        let speedSpringDamping: Float
    }

    private init() {
        loadPresets()
    }

    private func loadPresets() {
        guard let bundle = Bundle.glassImitationMetalSourcesBundle(for: GlassPresetsManager.self),
              let jsonURL = bundle.url(forResource: "GlassPresets", withExtension: "json") else {
            print("GlassPresets: Failed to find GlassPresets.json")
            return
        }

        do {
            let data = try Data(contentsOf: jsonURL)
            presets = try JSONDecoder().decode([String: PresetData].self, from: data)
        } catch {
            print("GlassPresets: Failed to load presets: \(error)")
        }
    }

    private func colorFromHex(_ hex: String) -> UIColor {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }

        var rgbValue: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgbValue)

        if hexString.count == 8 {
            // RRGGBBAA
            let r = CGFloat((rgbValue & 0xFF000000) >> 24) / 255.0
            let g = CGFloat((rgbValue & 0x00FF0000) >> 16) / 255.0
            let b = CGFloat((rgbValue & 0x0000FF00) >> 8) / 255.0
            let a = CGFloat(rgbValue & 0x000000FF) / 255.0
            return UIColor(red: r, green: g, blue: b, alpha: a)
        } else {
            // RRGGBB
            let r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
            let g = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
            let b = CGFloat(rgbValue & 0x0000FF) / 255.0
            return UIColor(red: r, green: g, blue: b, alpha: 1.0)
        }
    }

    public func parameters(for preset: GlassPreset) -> GlassParameters {
        guard let data = presets[preset.rawValue] else {
            fatalError("GlassPresets: Missing preset '\(preset.rawValue)' in GlassPresets.json")
        }

        return GlassParameters(
            glassCenter: CGPoint(x: 0.5, y: 0.5),
            cornerRadius: data.cornerRadius,
            refraction: data.refraction,
            edgeThickness: data.edgeThickness,
            edgeBlur: data.edgeBlur,
            chromaticStrength: data.chromaticStrength,
            overlayColor: colorFromHex(data.overlayColorHex),
            contentBlur: data.contentBlur,
            distortionExponent: data.distortionExponent,
            distortionDamping: data.distortionDamping,
            chromaticExponent: data.chromaticExponent,
            innerShadowBlur: data.innerShadowBlur,
            innerShadowOpacity: data.innerShadowOpacity,
            innerShadowColor: colorFromHex(data.innerShadowColorHex),
            innerShadowTopGradient: data.innerShadowTopGradient,
            borderWidth: data.borderWidth,
            borderColor: colorFromHex(data.borderColorHex),
            borderRefraction: data.borderRefraction
        )
    }

    public func settings(for preset: GlassPreset) -> GlassViewSettings {
        guard let data = presets[preset.rawValue] else {
            fatalError("GlassPresets: Missing preset '\(preset.rawValue)' in GlassPresets.json")
        }

        return GlassViewSettings(
            liveAnimationUpdateFrequency: data.liveAnimationUpdateFrequency,
            liveAnimationCaptureScale: CGFloat(data.liveAnimationCaptureScale),
            sdfBlendAmount: data.sdfBlendAmount,
            expansion: data.expansion,
            speedSpringStiffness: data.speedSpringStiffness,
            speedSpringDamping: data.speedSpringDamping
        )
    }
}

extension GlassView {
    public convenience init(preset: GlassPreset, alwaysLiquid: Bool = false) {
        let params = GlassPresetsManager.shared.parameters(for: preset)
        let settings = GlassPresetsManager.shared.settings(for: preset)
        self.init(parameters: params, settings: settings, alwaysLiquid: alwaysLiquid)
    }
}
