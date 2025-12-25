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
import Accelerate


public final class GlassView : UIView {

    public enum CaptureMethod {
        case render
        case drawHierarchy
    }

    deinit {
        cachedRawData?.deallocate()
        cachedFlipBuffer?.deallocate()
    }

    //MARK: - Public -

    public var parameters: GlassParameters
    public var textureFillColor: UIColor? 
    
    public weak var textureSourceView: UIView? {
        didSet {
            needsTextureUpdate = true
            if let sourceView = textureSourceView {
                lastSourceViewFrame = sourceView.layer.presentation()?.frame ?? sourceView.frame
                lastSourceViewTransform = sourceView.layer.presentation()?.affineTransform() ?? sourceView.transform
            } else {
                lastSourceViewFrame = .zero
                lastSourceViewTransform = .identity
            }
        }
    }

    public var highlightScale: Float = 1.0
    public var viewsToHideDuringCapture: [UIView] = []
    public var viewsToUnhideDuringCapture: [UIView] = []
    public var captureMethod: CaptureMethod = .render

    public private(set) var speed: Float = 0.0
    public private(set) var isLiveAnimating = false

    public var participatesInMerge: Bool = true


    //MARK: - Helpers -

    public override var frame: CGRect {
        didSet {
            if frame.origin != oldValue.origin || frame.size != oldValue.size {
                needsTextureUpdate = true
                registry?.notifyAll()
            }
        }
    }
    
    public override var bounds: CGRect {
        didSet {
            if bounds.size != oldValue.size {
                needsTextureUpdate = true
                registry?.notifyAll()
            }
        }
    }
    
    public override var transform: CGAffineTransform {
        didSet {
            if transform != oldValue {
                needsTextureUpdate = true
                registry?.notifyAll()
            }
        }
    }

    public override var alpha: CGFloat {
        didSet {
            if alpha != oldValue {
                registry?.notifyAll()
            }
        }
    }

    public override var isHidden: Bool {
        didSet {
            if isHidden != oldValue {
                registry?.notifyAll()
            }
        }
    }


    //MARK: - Private -

    private var settings: GlassViewSettings
    private(set) var registry: GlassViewRegistry?
    
    private var alwaysLiquid: Bool = false

    /// Speed for squash effect: >0 squash vertically (moving right), <0 squash horizontally (moving left)
    private var speedPeakValue: Float = 0.0
    private var speedAnimationStartTime: CFTimeInterval = 0.0
    private var speedAnimationDuration: CFTimeInterval = 0.3
    private var speedDisplayLink: CADisplayLink?

    private var highlightScaleTarget: Float = 1.0
    private var highlightScaleStart: Float = 1.0
    private var highlightAnimationStartTime: CFTimeInterval = 0.0
    private var highlightAnimationDuration: CFTimeInterval = 0.2
    private var highlightDisplayLink: CADisplayLink?

    //Metal
    private var metalView: MTKView!
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var texture: MTLTexture?
    private var textureCache: CVMetalTextureCache?

    // Texture
    private var cachedTextureSize: (width: Int, height: Int) = (0, 0)

    private var cachedRawData: UnsafeMutableRawPointer?
    private var cachedRawDataSize: Int = 0
    private var cachedFlipBuffer: UnsafeMutableRawPointer?
    private var cachedFlipBufferSize: Int = 0
    private var cachedContext: CGContext?
    private var cachedContextSize: (width: Int, height: Int) = (0, 0)
    private static let sharedColorSpace = CGColorSpaceCreateDeviceRGB()
    
    //State
    private var originalBounds: CGRect = .zero
    private var needsTextureUpdate = true
    private var isCapturing = false
    private var displayLink: CADisplayLink?
    private var frameCounter = 0
    private var lastSourceViewFrame: CGRect = .zero
    private var lastSourceViewTransform: CGAffineTransform = .identity
    private var lastGlassViewFrame: CGRect = .zero
    private var wasAnimating: Bool = false
    
    
    //MARK: - System -

    public init(parameters: GlassParameters,
                settings: GlassViewSettings,
                alwaysLiquid: Bool = false) {

        self.parameters = parameters
        self.settings = settings
        self.alwaysLiquid = alwaysLiquid

        super.init(frame: .zero)
        
        setupUI()
        setupMetal()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        needsTextureUpdate = true
        
        if superview != nil {
            registry?.register(self)
        } else {
            registry?.unregister(self)
        }
    }
    
    public override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)
        if newSuperview == nil {
            registry?.unregister(self)
            stopLiveAnimating()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let expansion = CGFloat(settings.expansion)
        metalView?.frame = bounds.insetBy(dx: -expansion, dy: -expansion)
    }


    //MARK: - Setup -
    
    private func setupUI() {
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
    }
    
    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }
        
        self.device = device
        
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        
        setupMetalView(device: device)
        setupRenderPipeline(device: device)
    }
    
    private func setupMetalView(device: MTLDevice) {
        let expansion = CGFloat(settings.expansion)
        let expandedFrame = bounds.insetBy(dx: -expansion, dy: -expansion)

        metalView = MTKView(frame: expandedFrame, device: device)
        metalView.delegate = self
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        metalView.isOpaque = false
        metalView.backgroundColor = .clear
        metalView.isPaused = !alwaysLiquid
        metalView.enableSetNeedsDisplay = !alwaysLiquid
        metalView.clipsToBounds = false
        metalView.layer.masksToBounds = false
        addSubview(metalView)

        commandQueue = device.makeCommandQueue()
    }
    
    private func setupRenderPipeline(device: MTLDevice) {
        
        guard
            let library = device.createLibrary() else {
            print("Failed to create default library")
            return
        }
        
        let vertexFunction = library.makeFunction(name: "glass_vertex_main")
        let fragmentFunction = library.makeFunction(name: "glass_fragment_main")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create pipeline state: \(error)")
        }
    }


    //MARK: - Capture -
    
    private func captureUnderlyingView() -> MTLTexture? {
        guard !isCapturing else { return texture }

        let captureSource: UIView
        let useCustomSource: Bool

        if let customSource = textureSourceView {
            captureSource = customSource
            useCustomSource = true
        } else if let sv = superview {
            captureSource = sv
            useCustomSource = false
        } else {
            return texture
        }

        isCapturing = true
        defer { isCapturing = false }

        let captureScale = settings.liveAnimationCaptureScale
        let scale = UIScreen.main.scale * captureScale

        let expansion = CGFloat(settings.expansion)
        let expandedSize = CGSize(
            width: bounds.width + expansion * 2,
            height: bounds.height + expansion * 2
        )
        let width = Int(expandedSize.width * scale)
        let height = Int(expandedSize.height * scale)

        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = width * 4
        let totalBytes = bytesPerRow * height
        let sizeChanged = cachedTextureSize.width != width || cachedTextureSize.height != height

        let targetTexture: MTLTexture
        if !sizeChanged, let existingTexture = texture {
            targetTexture = existingTexture
        } else {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead, .renderTarget]

            guard let newTexture = device.makeTexture(descriptor: descriptor) else {
                return nil
            }
            targetTexture = newTexture
            cachedTextureSize = (width, height)
        }

        if cachedRawDataSize < totalBytes {
            cachedRawData?.deallocate()
            cachedRawData = UnsafeMutableRawPointer.allocate(byteCount: totalBytes, alignment: 64)
            cachedRawDataSize = totalBytes
            cachedContext = nil
        }

        guard let rawData = cachedRawData else { return nil }

        let context: CGContext
        if cachedContextSize.width == width,
           cachedContextSize.height == height,
           let existingContext = cachedContext {
            context = existingContext
        } else {
            guard let newContext = CGContext(
                data: rawData,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: Self.sharedColorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return nil
            }
            cachedContext = newContext
            cachedContextSize = (width, height)
            context = newContext
        }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()

        if let fillColor = textureFillColor {
            context.setFillColor(fillColor.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }

        let animatedFrame = layer.presentation()?.frame ?? frame
        let offsetX: CGFloat
        let offsetY: CGFloat

        if useCustomSource, let sv = superview {
            let frameInSource = sv.convert(animatedFrame, to: captureSource)
            offsetX = -(frameInSource.minX - expansion)
            offsetY = -(frameInSource.minY - expansion)
        } else {
            offsetX = -(animatedFrame.minX - expansion)
            offsetY = -(animatedFrame.minY - expansion)
        }

        // Transform for UIKit coordinate system
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: offsetX, y: offsetY)

        let glassViews = registry?.getAllViews() ?? []
        let glassHiddenStates = glassViews.map { view -> Bool in
            let wasHidden = view.isHidden
            view.isHidden = true
            return wasHidden
        }
        let excludedOpacities = viewsToHideDuringCapture.map { view -> Float in
            let opacity = view.layer.opacity
            view.layer.opacity = 0
            return opacity
        }
        let unhiddenStates = viewsToUnhideDuringCapture.map { view -> Bool in
            let wasHidden = view.isHidden
            view.isHidden = false
            return wasHidden
        }

        // Render
        switch captureMethod {
        case .render:
            (captureSource.layer.presentation() ?? captureSource.layer).render(in: context)
        case .drawHierarchy:
            UIGraphicsPushContext(context)
            captureSource.drawHierarchy(in: CGRect(origin: .zero, size: captureSource.bounds.size), afterScreenUpdates: false)
            UIGraphicsPopContext()
        }

        for (i, view) in glassViews.enumerated() {
            view.isHidden = glassHiddenStates[i]
        }
        for (i, view) in viewsToHideDuringCapture.enumerated() {
            view.layer.opacity = excludedOpacities[i]
        }
        for (i, view) in viewsToUnhideDuringCapture.enumerated() {
            view.isHidden = unhiddenStates[i]
        }

        context.restoreGState()

        // Upload to texture
        targetTexture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: rawData,
            bytesPerRow: bytesPerRow
        )

        return targetTexture
    }


    //MARK: - Animation/Live -
    
    public func setCoordinator(_ coordinator: GlassViewRegistry) {
        self.registry = coordinator
        coordinator.register(self)
    }
    
    public func startLiveAnimating(refreshTexture: Bool = true) {
        isLiveAnimating = true
        frameCounter = 0
        if refreshTexture {
            needsTextureUpdate = true
        }
        if !alwaysLiquid {
            metalView?.isPaused = false
        }

        if let sourceView = textureSourceView {
            lastSourceViewFrame = sourceView.layer.presentation()?.frame ?? sourceView.frame
            lastSourceViewTransform = sourceView.layer.presentation()?.affineTransform() ?? sourceView.transform
        }
        lastGlassViewFrame = layer.presentation()?.frame ?? frame

        if displayLink == nil {
            displayLink = CADisplayLink(target: self, selector: #selector(liveUpdate))
            displayLink?.add(to: .main, forMode: .common)
        }
    }

    public func stopLiveAnimating() {
        isLiveAnimating = false
        displayLink?.invalidate()
        displayLink = nil
        if !alwaysLiquid {
            metalView?.isPaused = true
        }
    }
    
    @objc private func liveUpdate() {
        frameCounter += 1

        // Check if source view or glass view has moved - only then update texture
        let currentGlassFrame = layer.presentation()?.frame ?? frame
        var sourceChanged = false

        if let sourceView = textureSourceView {
            let currentSourceFrame = sourceView.layer.presentation()?.frame ?? sourceView.frame
            let currentSourceTransform = sourceView.layer.presentation()?.affineTransform() ?? sourceView.transform

            if currentSourceFrame != lastSourceViewFrame ||
               currentSourceTransform != lastSourceViewTransform {
                lastSourceViewFrame = currentSourceFrame
                lastSourceViewTransform = currentSourceTransform
                sourceChanged = true
            }
        }

        let glassChanged = currentGlassFrame != lastGlassViewFrame
        if glassChanged {
            lastGlassViewFrame = currentGlassFrame
        }

        if sourceChanged || glassChanged || alwaysLiquid {
            needsTextureUpdate = true
        }
    }
    
    public func refreshTexture() {
        needsTextureUpdate = true
        metalView?.setNeedsDisplay()
    }


    //MARK: - Hightlight Scale 
    
    public func setHighlightScale(_ scale: Float, animated: Bool) {
        highlightScaleTarget = scale
        registry?.notifyAll()

        if animated {
            highlightScaleStart = highlightScale
            highlightAnimationStartTime = CACurrentMediaTime()
            if highlightDisplayLink == nil {
                highlightDisplayLink = CADisplayLink(target: self, selector: #selector(updateHighlightAnimation))
                highlightDisplayLink?.add(to: .main, forMode: .common)
            }
        } else {
            highlightScale = scale
            highlightDisplayLink?.invalidate()
            highlightDisplayLink = nil
            registry?.notifyAll()
        }
    }

    @objc 
    private func updateHighlightAnimation() {
        let elapsed = CACurrentMediaTime() - highlightAnimationStartTime
        let t = Float(min(elapsed / highlightAnimationDuration, 1.0))

        // Ease out cubic (faster start)
        let eased = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t)
        highlightScale = highlightScaleStart + (highlightScaleTarget - highlightScaleStart) * eased

        registry?.notifyAll()

        if elapsed >= highlightAnimationDuration {
            highlightScale = highlightScaleTarget
            highlightDisplayLink?.invalidate()
            highlightDisplayLink = nil
        }
    }

    //MARK: - Speed Pulse 

    /// Animates speed from 0 → peak → 0 over the given duration (synced with frame animation)
    public func animateSpeedPulse(to peakSpeed: Float, duration: CFTimeInterval) {
        speedPeakValue = peakSpeed
        speedAnimationStartTime = CACurrentMediaTime()
        speedAnimationDuration = duration
        if speedDisplayLink == nil {
            speedDisplayLink = CADisplayLink(target: self, selector: #selector(updateSpeedAnimation))
            speedDisplayLink?.add(to: .main, forMode: .common)
        }
    }

    @objc private func updateSpeedAnimation() {
        let elapsed = CACurrentMediaTime() - speedAnimationStartTime
        let t = Float(min(elapsed / speedAnimationDuration, 1.0))

        let pulse = sin(t * .pi)
        speed = speedPeakValue * pulse

        if elapsed >= speedAnimationDuration {
            speed = 0.0
            speedDisplayLink?.invalidate()
            speedDisplayLink = nil
        }
    }
}


//MARK: - MTKViewDelegate -

extension GlassView: MTKViewDelegate {
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        needsTextureUpdate = true
    }
    
    public func draw(in view: MTKView) {

        guard let pipelineState else {
            return
        }

        if needsTextureUpdate || texture == nil {
            texture = captureUnderlyingView()
            needsTextureUpdate = false
        }

        guard let texture = texture,
              let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        let expansion = CGFloat(settings.expansion)
        var instances = registry?.getInstances(for: self, expansion: settings.expansion) ?? []

        // If no registry, create a single instance for this view
        if instances.isEmpty {
            instances = [GlassInstance(
                position: SIMD2<Float>(Float(expansion), Float(expansion)),
                size: SIMD2<Float>(Float(bounds.width), Float(bounds.height)),
                cornerRadius: parameters.cornerRadius
            )]
        }

        let expandedWidth = bounds.width + expansion * 2
        let expandedHeight = bounds.height + expansion * 2

        var uniforms = GlassUniforms(
            size: SIMD2<Float>(Float(expandedWidth), Float(expandedHeight)),
            parameters: parameters,
            instanceCount: instances.count,
            sdfBlendAmount: settings.sdfBlendAmount,
            speed: speed,
            highlightScale: highlightScale
        )

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFragmentTexture(texture, index: 0)
        renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<GlassUniforms>.stride, index: 0)

        // Pass instances array to shader (always set this buffer since shader expects it)
        renderEncoder.setFragmentBytes(&instances, length: MemoryLayout<GlassInstance>.stride * instances.count, index: 1)

        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        renderEncoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

