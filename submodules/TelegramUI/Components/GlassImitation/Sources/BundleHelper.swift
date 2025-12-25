//
//  LibraryCreator.swift
//  GlassImitation
//
//  Created by iN 
//

import Foundation
import Metal
import MetalKit

public extension MTLDevice {
    func createLibrary() -> MTLLibrary? {
        if let bundle = Bundle.glassImitationMetalSourcesBundle(for: GlassView.self),
           let library = try? makeDefaultLibrary(bundle: bundle) {
            return library
        }
        return nil
    }
}

public extension Bundle {
    static func glassImitationMetalSourcesBundle(for aClass: AnyClass) -> Bundle? {
       if let bundleURL = Bundle(for: aClass).url(forResource: "GlassImitationMetalSourcesBundle", withExtension: "bundle") {
            let bundle = Bundle(url: bundleURL)
            return bundle
        }
        return nil
    }
}