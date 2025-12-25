#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct GlassInstance {
    float2 position;  // Top-left position in superview coordinates
    float2 size;
    float cornerRadius;
};

struct GlassUniforms {
    float2 size;
    float2 glassCenter;
    float cornerRadius;
    float refraction;
    float edgeThickness;
    float edgeBlur;
    float chromaticStrength;
    float4 overlayColor;
    int instanceCount;
    float sdfBlendAmount;  // Controls liquid blending amount
    float speed;  // Squash factor: >0 squash vertically, <0 squash horizontally
    float contentBlur;  // Blur amount for content (0 = no blur)
    float highlightScale;  // Scale factor for self instance (1.0 = normal)
    float distortionExponent;  // Exponent for distortion falloff curve (default 3.0)
    float distortionDamping;  // Reduces distortion at edges (default 0.3)
    float chromaticExponent;  // Exponent for chromatic aberration falloff (default 4.0)
    float innerShadowBlur;  // Blur/spread of inner shadow (in pixels)
    float innerShadowOpacity;  // Opacity of inner shadow
    float innerShadowTopGradient;  // Height of top gradient shadow (0 = disabled)
    float borderWidth;  // Width of border in pixels
    float borderRefraction;  // Refraction multiplier for border area
    float _padding;  // Padding for alignment
    float4 innerShadowColor;  // Color of inner shadow
    float4 borderColor;  // Color of border
};

// Box blur sampling function
float4 blurSample(texture2d<float> tex, sampler s, float2 uv, float2 texelSize, float blurAmount) {
    if (blurAmount <= 0.0) {
        return tex.sample(s, uv);
    }

    float4 color = float4(0.0);
    float total = 0.0;
    int radius = int(blurAmount);

    for (int x = -radius; x <= radius; x++) {
        for (int y = -radius; y <= radius; y++) {
            float2 offset = float2(float(x), float(y)) * texelSize;
            color += tex.sample(s, uv + offset);
            total += 1.0;
        }
    }

    return color / total;
}

// === SDF FUNCTIONS ===

// Rounded box SDF
float roundedBoxSDF(float2 p, float2 center, float2 size, float radius) {
    float2 d = abs(p - center) - size * 0.5 + radius;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
}

// Smooth union for organic blending
float smoothUnion(float d1, float d2, float k) {
    float h = max(k - abs(d1 - d2), 0.0) / k;
    return min(d1, d2) - h * h * k * 0.25;
}

// Smooth intersection
float smoothIntersection(float d1, float d2, float k) {
    float h = max(k - abs(d1 - d2), 0.0) / k;
    return max(d1, d2) + h * h * k * 0.25;
}

// Smooth subtraction
float smoothSubtraction(float d1, float d2, float k) {
    float h = max(k - abs(d1 + d2), 0.0) / k;
    return max(d1, -d2) + h * h * k * 0.25;
}

vertex VertexOut glass_vertex_main(uint vertexID [[vertex_id]]) {
    // Full-screen triangle
    float2 positions[3] = {
        float2(-1, -1),
        float2( 3, -1),
        float2(-1,  3)
    };
    
    float2 texCoords[3] = {
        float2(0, 0),
        float2(2, 0),
        float2(0, 2)
    };
    
    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

fragment float4 glass_fragment_main(
    VertexOut in [[stage_in]],
    texture2d<float> layer [[texture(0)]],
    constant GlassUniforms &uniforms [[buffer(0)]],
    constant GlassInstance *instances [[buffer(1)]]
) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    // Normalize UV coordinates (0 to 1)
    float2 uv = in.texCoord;
    
    // Calculate distance from glass center for effects
    float2 toCenter = uv - float2(0.5, 0.5);
    
    // Normalize distance by actual size to account for aspect ratio
    float2 normalizedToCenter = toCenter * uniforms.size / max(uniforms.size.x, uniforms.size.y);
    float normalizedDist = length(normalizedToCenter) * 2.0; // *2 because toCenter ranges from -0.5 to 0.5

    // Pixel position in local view space
    float2 pixelPos = uv * uniforms.size;
    float2 rectCenter = uniforms.size * 0.5;
    
    // === APPLY SPEED SQUASH TO PIXEL POSITION ===
    // speed > 0 (moving right): squash Y (taller but not as much as moving left), stretch X (wider)
    // speed < 0 (moving left): stretch Y (taller), squash X (narrower)
    float2 squashedPixelPos = pixelPos;
    if (abs(uniforms.speed) > 0.001) {
        float2 center = uniforms.size * 0.5;
        float2 fromCenter = pixelPos - center;
        float squashAmount = abs(uniforms.speed);
        if (uniforms.speed > 0) {
            // Moving right: squash Y (taller but not as much as moving left), stretch X (wider)
            fromCenter.y /= (1.0 + squashAmount * 0.7);
            fromCenter.x /= (1.0 + squashAmount);
        } else {
            // Moving left: stretch Y (taller), squash X (narrower)
            fromCenter.y /= (1.0 + squashAmount * 1.4);
            fromCenter.x /= (1.0 + squashAmount * 0.9);
        }
        squashedPixelPos = center + fromCenter;
    }

    // === SDF COMPUTATION FOR LIQUID EFFECT ===
    float distToRoundedRect;
    float selfSDF = 1e10;  // SDF for this view only (instance 0)

    if (uniforms.instanceCount > 0) {
        // Compute SDF field combining all glass instances
        float combinedSDF = 1e10;
        float scale = uniforms.highlightScale > 0.0 ? uniforms.highlightScale : 1.0;

        for (int i = 0; i < uniforms.instanceCount && i < 32; i++) {
            GlassInstance inst = instances[i];

            // Apply highlight scale to self instance (i == 0)
            float2 instSize = inst.size;
            float instCornerRadius = inst.cornerRadius;
            if (i == 0 && scale != 1.0) {
                instSize = inst.size * scale;
                instCornerRadius = inst.cornerRadius * scale;
            }

            float2 instCenter = inst.position + inst.size * 0.5;  // Center stays the same
            float sdf = roundedBoxSDF(squashedPixelPos, instCenter, instSize, instCornerRadius);

            if (i == 0) {
                selfSDF = sdf;
                combinedSDF = sdf;
            } else {
                combinedSDF = smoothUnion(combinedSDF, sdf, uniforms.sdfBlendAmount);
            }
        }

        distToRoundedRect = combinedSDF;

        // Only skip pixels that are INSIDE another instance (not in blend zone)
        // This view renders: its own shape + blend zones extending from it
        if (uniforms.instanceCount > 1 && selfSDF > 0) {
            // We're outside our own shape - check if inside another
            for (int i = 1; i < uniforms.instanceCount && i < 32; i++) {
                GlassInstance inst = instances[i];
                float2 instCenter = inst.position + inst.size * 0.5;
                float otherSDF = roundedBoxSDF(squashedPixelPos, instCenter, inst.size, inst.cornerRadius);

                // If inside another instance (not in blend zone), skip
                if (otherSDF < -uniforms.sdfBlendAmount * 0.5) {
                    return float4(0.0, 0.0, 0.0, 0.0);
                }
            }
        }

        // Use selfSDF for inside check - render this view's shape plus blend extensions
        distToRoundedRect = selfSDF < 0 ? selfSDF : distToRoundedRect;
    } else if (uniforms.instanceCount > 0) {
        // Not in liquid mode, use first instance (this view itself)
        GlassInstance inst = instances[0];
        float scale = uniforms.highlightScale > 0.0 ? uniforms.highlightScale : 1.0;
        float2 instSize = inst.size * scale;
        float instCornerRadius = inst.cornerRadius * scale;
        float2 instCenter = inst.position + inst.size * 0.5;
        distToRoundedRect = roundedBoxSDF(squashedPixelPos, instCenter, instSize, instCornerRadius);
    } else {
        // Fallback: use center of expanded area
        float2 rectPos = squashedPixelPos - rectCenter;
        float2 rectHalfSize = (uniforms.size - uniforms.sdfBlendAmount * 2.0) * 0.5;
        float2 q = abs(rectPos) - rectHalfSize + uniforms.cornerRadius;
        distToRoundedRect = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - uniforms.cornerRadius;
    }
    
    bool insideGlass = distToRoundedRect < 0.0;
    
    // If not in glass, return transparent
    if (!insideGlass) {
        return float4(0.0, 0.0, 0.0, 0.0);
    }

    // Sample background for glass effects
    float2 texelSize = 1.0 / uniforms.size;
    float4 result = blurSample(layer, textureSampler, uv, texelSize, uniforms.contentBlur);

    // === 1. REFRACTION WITH CHROMATIC ABERRATION ===
    if (insideGlass) {
        float distortion = pow(normalizedDist, uniforms.distortionExponent) * (1.0 - normalizedDist * uniforms.distortionDamping);
        float2 position = uv * uniforms.size;
        float2 offset = toCenter * distortion * uniforms.refraction;
        float2 refractedPosition = position - (offset * uniforms.size);
        float2 refractedUV = refractedPosition / uniforms.size;

        if (uniforms.chromaticStrength > 0.0) {
            float edgeFactor = pow(normalizedDist, uniforms.chromaticExponent);
            float chromatic = edgeFactor * uniforms.chromaticStrength;
            float2 redPos = refractedPosition - (toCenter * uniforms.size * chromatic);
            float2 bluePos = refractedPosition + (toCenter * uniforms.size * chromatic);

            result.r = blurSample(layer, textureSampler, redPos / uniforms.size, texelSize, uniforms.contentBlur).r;
            result.g = blurSample(layer, textureSampler, refractedUV, texelSize, uniforms.contentBlur).g;
            result.b = blurSample(layer, textureSampler, bluePos / uniforms.size, texelSize, uniforms.contentBlur).b;
        } else {
            result = blurSample(layer, textureSampler, refractedUV, texelSize, uniforms.contentBlur);
        }
    }

    // === 2. EDGE HIGHLIGHT ===
    if (insideGlass && uniforms.edgeThickness > 0.0) {
        float distToEdge = -distToRoundedRect;
        float maxDim = max(uniforms.size.x, uniforms.size.y);
        float thicknessPx = uniforms.edgeThickness * maxDim;
        float blurPx = uniforms.edgeBlur * maxDim;
        float edgeFade = 1.0 - smoothstep(0.0, thicknessPx + blurPx, distToEdge);
        result.rgb += edgeFade * uniforms.edgeBlur;
    }

    // === 3. OVERLAY COLOR BLEND ===
    if (uniforms.overlayColor.a > 0.0) {
        result.rgb = mix(result.rgb, uniforms.overlayColor.rgb, uniforms.overlayColor.a);
    }

    // === 4. INNER SHADOW ===
    if (uniforms.innerShadowOpacity > 0.0 && uniforms.innerShadowBlur > 0.0) {
        // Distance from edge (positive when inside)
        float distFromEdge = -distToRoundedRect;
        // Calculate shadow intensity based on distance from edge
        float shadowIntensity = 1.0 - smoothstep(0.0, uniforms.innerShadowBlur, distFromEdge);
        shadowIntensity *= uniforms.innerShadowOpacity;
        // Blend shadow color
        result.rgb = mix(result.rgb, uniforms.innerShadowColor.rgb, shadowIntensity);
    }

    // === 5. INNER SHADOW TOP/BOTTOM GRADIENT ===
    if (uniforms.innerShadowTopGradient != 0.0 && uniforms.innerShadowOpacity > 0.0) {
        float gradientHeight = abs(uniforms.innerShadowTopGradient);

        float gradient;
        if (uniforms.innerShadowTopGradient > 0.0) {
            // Positive: gradient from top downward
            // uv.y = 0 at bottom, 1 at top in Metal, so use uv.y directly
            float distFromTop = (1.0 - uv.y) * uniforms.size.y;
            gradient = 1.0 - smoothstep(0.0, gradientHeight, distFromTop);
        } else {
            // Negative: gradient from bottom upward
            float distFromBottom = uv.y * uniforms.size.y;
            gradient = 1.0 - smoothstep(0.0, gradientHeight, distFromBottom);
        }

        gradient *= uniforms.innerShadowOpacity;
        result.rgb = mix(result.rgb, uniforms.innerShadowColor.rgb, gradient);
    }

    // === 6. BORDER WITH ENHANCED REFRACTION ===
    if (uniforms.borderWidth > 0.0 && uniforms.borderColor.a > 0.0) {
        float distFromEdge = -distToRoundedRect;
        // Border zone: from edge (0) to borderWidth
        float borderFactor = 1.0 - smoothstep(0.0, uniforms.borderWidth, distFromEdge);

        if (borderFactor > 0.0) {
            // Enhanced refraction in border area
            float borderDistortion = pow(normalizedDist, uniforms.distortionExponent) * (1.0 - normalizedDist * uniforms.distortionDamping);
            float2 borderOffset = toCenter * borderDistortion * uniforms.refraction * uniforms.borderRefraction;
            float2 borderRefractedUV = (uv * uniforms.size - borderOffset * uniforms.size) / uniforms.size;

            float4 borderSample = blurSample(layer, textureSampler, borderRefractedUV, texelSize, uniforms.contentBlur);

            // Blend border color with enhanced refraction
            float3 borderResult = mix(borderSample.rgb, uniforms.borderColor.rgb, uniforms.borderColor.a);
            result.rgb = mix(result.rgb, borderResult, borderFactor);
        }
    }

    return result;
}