// ═══════════════════════════════════════════════════════════════════
//  artistic_painterly_oil
//  Category: artistic
//  Features: upgraded-rgba, depth-aware, physical-media-alpha
//  Upgraded: 2026-03-22
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn sobel(uv: vec2<f32>, invRes: vec2<f32>) -> vec2<f32> {
    let sx = array<f32, 9>(-1.0, 0.0, 1.0, -2.0, 0.0, 2.0, -1.0, 0.0, 1.0);
    let sy = array<f32, 9>(-1.0, -2.0, -1.0, 0.0, 0.0, 0.0, 1.0, 2.0, 1.0);
    
    let offsets = array<vec2<f32>, 9>(
        vec2<f32>(-1.0, -1.0), vec2<f32>(0.0, -1.0), vec2<f32>(1.0, -1.0),
        vec2<f32>(-1.0,  0.0), vec2<f32>(0.0,  0.0), vec2<f32>(1.0,  0.0),
        vec2<f32>(-1.0,  1.0), vec2<f32>(0.0,  1.0), vec2<f32>(1.0,  1.0)
    );
    
    var gx = 0.0;
    var gy = 0.0;
    
    for (var i: i32 = 0; i < 9; i = i + 1) {
        let lum = luminance(textureSampleLevel(readTexture, u_sampler, uv + offsets[i] * invRes, 0.0).rgb);
        gx += lum * sx[i];
        gy += lum * sy[i];
    }
    
    return vec2<f32>(gx, gy);
}

fn kuwahara(uv: vec2<f32>, invRes: vec2<f32>, radius: i32, edgeDir: vec2<f32>) -> vec3<f32> {
    var mean = vec3<f32>(0.0);
    var variance = 0.0;
    var bestMean = vec3<f32>(0.0);
    var minVariance = 999999.0;
    
    let perp = vec2<f32>(-edgeDir.y, edgeDir.x);
    
    for (var sector: i32 = 0; sector < 4; sector = sector + 1) {
        mean = vec3<f32>(0.0);
        variance = 0.0;
        
        for (var y: i32 = 0; y < radius; y = y + 1) {
            for (var x: i32 = 0; x < radius; x = x + 1) {
                var offset: vec2<f32>;
                switch(sector) {
                    case 0: { offset = vec2<f32>( f32(x),  f32(y)); }
                    case 1: { offset = vec2<f32>(-f32(x),  f32(y)); }
                    case 2: { offset = vec2<f32>( f32(x), -f32(y)); }
                    case 3: { offset = vec2<f32>(-f32(x), -f32(y)); }
                    default: { offset = vec2<f32>(0.0); }
                }
                
                offset = edgeDir * offset.x * 2.0 + perp * offset.y * 0.5;
                
                let sampleUV = uv + offset * invRes;
                let col = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
                
                mean += col;
                variance += luminance(col * col);
            }
        }
        
        let sectorSamples = f32(radius * radius);
        mean /= sectorSamples;
        variance = variance / sectorSamples - luminance(mean) * luminance(mean);
        
        if (variance < minVariance) {
            minVariance = variance;
            bestMean = mean;
        }
    }
    
    return bestMean;
}

fn quantizeColor(c: vec3<f32>, levels: i32) -> vec3<f32> {
    let fLevels = f32(levels);
    return floor(c * fLevels) / fLevels;
}

fn impastoHeight(lum: f32, edgeMag: f32) -> f32 {
    return lum * 0.5 + edgeMag * 0.5;
}

fn wetPaintSpecular(color: vec3<f32>, normal: vec2<f32>, lightDir: vec2<f32>) -> vec3<f32> {
    let viewDir = vec2<f32>(0.0, 1.0);
    let halfDir = normalize(lightDir + viewDir);
    let specAngle = max(dot(normalize(vec3<f32>(normal, 1.0)), vec3<f32>(halfDir, 1.0)), 0.0);
    let specular = pow(specAngle, 32.0);
    
    return vec3<f32>(specular * 0.3);
}

fn canvasTexture(uv: vec2<f32>, scale: f32) -> f32 {
    let grid = sin(uv.x * scale * 100.0) * sin(uv.y * scale * 100.0);
    return grid * 0.5 + 0.5;
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let invRes = 1.0 / resolution;
    let time = u.config.x;
    
    // Parameters
    let brushSize = i32(3.0 + u.zoom_params.x * 8.0);
    let paintWetness = u.zoom_params.y;
    let colorLevels = i32(2.0 + u.zoom_params.z * 6.0);
    let impastoStrength = u.zoom_params.w;
    
    // Edge detection for anisotropic direction
    let edge = sobel(uv, invRes);
    let edgeMag = length(edge);
    let edgeDir = normalize(edge + vec2<f32>(0.001));
    
    // Apply anisotropic Kuwahara filter
    var color = kuwahara(uv, invRes, brushSize, edgeDir);
    
    // Color quantization
    color = quantizeColor(color, colorLevels);
    
    // Impasto effect - calculate physical paint height
    let lum = luminance(color);
    let height = impastoHeight(lum, edgeMag);
    
    // Normal from height for lighting
    let heightR = impastoHeight(luminance(kuwahara(uv + vec2<f32>(invRes.x, 0.0), invRes, brushSize, edgeDir)), edgeMag);
    let heightU = impastoHeight(luminance(kuwahara(uv + vec2<f32>(0.0, invRes.y), invRes, brushSize, edgeDir)), edgeMag);
    let normal = normalize(vec2<f32>(height - heightR, height - heightU) * 10.0);
    
    // Wet paint specular
    let lightDir = normalize(vec2<f32>(cos(time * 0.5), sin(time * 0.5)));
    let specular = wetPaintSpecular(color, normal, lightDir);
    color += specular * paintWetness;
    
    // Canvas texture
    let canvas = canvasTexture(uv, 1.0);
    color = mix(color, color * (0.9 + canvas * 0.2), 0.15);
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.4;
    color *= vignette;
    
    // OIL PAINT PHYSICAL MEDIA ALPHA CALCULATION
    // Oil paint has unique transparency characteristics:
    // - Impasto (thick): opaque, texture visible (alpha ~0.9-0.98)
    // - Medium body: semi-opaque (alpha ~0.6-0.85)
    // - Glaze (thin): translucent, allows underlayers (alpha ~0.3-0.6)
    // - Canvas showing through: substrate visible
    
    // Canvas texture for paint interaction
    let canvas_tex = hash12(uv * 100.0) * 0.1 + 0.9;
    
    // PAINT THICKNESS → ALPHA MAPPING
    // Height map from impasto calculation
    let paint_thickness = height * (0.5 + impastoStrength);
    
    // Base alpha from thickness
    // Thick paint = more pigment = more opaque
    var paint_alpha = mix(0.35, 0.96, paint_thickness * paint_thickness);
    
    // Wet paint is more translucent than dry paint
    // (Light penetrates wet paint, bounces within, exits)
    let dry_factor = 1.0 - paintWetness * 0.3;
    paint_alpha *= dry_factor;
    
    // Canvas weave creates variation in paint coverage
    // Valleys hold more paint, peaks may show through in thin areas
    let weave_effect = mix(0.92, 1.0, canvas_tex);
    paint_alpha *= weave_effect;
    
    // Edge areas of brush strokes have thinner paint
    let stroke_edge = smoothstep(0.0, 0.4, edgeMag);
    paint_alpha *= mix(0.85, 1.0, stroke_edge);
    
    // Pigment density affects opacity
    // Darker colors often have more pigment and are more opaque
    let pigment_density = 1.0 - lum;
    let opacity_boost = mix(0.0, 0.1, pigment_density * impastoStrength);
    paint_alpha = min(1.0, paint_alpha + opacity_boost);
    
    // Color modification based on thickness
    // Thick impasto = deeper, richer color
    // Thin glaze = lighter, more luminous
    let thickness_luma = mix(1.15, 0.9, paint_thickness);
    color *= thickness_luma;
    
    // Add slight warmth to thick areas (oil medium yellowing)
    let warm_tint = vec3<f32>(1.02, 1.0, 0.95);
    color = mix(color, color * warm_tint, paint_thickness * 0.3);
    
    // Specular highlight contributes to perceived solidity
    let spec_alpha = luminance(specular) * paintWetness * 0.5;
    paint_alpha = min(1.0, paint_alpha + spec_alpha);

    textureStore(writeTexture, coord, vec4<f32>(color, paint_alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(paint_thickness, 0.0, 0.0, paint_alpha));
    
    // Store filtered result with thickness for temporal continuity
    textureStore(dataTextureA, coord, vec4<f32>(color, paint_thickness));
}
