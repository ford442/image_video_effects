// ═══════════════════════════════════════════════════════════════════
//  Quantum Foam
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Created: 2026-04-15
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI:    f32 = 3.14159265358979323846;
const TAU:   f32 = 6.28318530717958647692;
const PHI:   f32 = 1.61803398874989484820;
const HBAR:  f32 = 1.0545718e-34;

fn hash3(p: vec3<f32>) -> f32 {
    let p3 = fract(p * vec3<f32>(443.897, 441.423, 997.731));
    return fract(p3.x * p3.y * p3.z + dot(p3, p3 + 19.19));
}

fn hash2(p: vec2<f32>) -> f32 {
    var p2 = fract(p * vec2<f32>(123.456, 789.012));
    p2 = p2 + dot(p2, p2 + 45.678);
    return fract(p2.x * p2.y);
}

fn noise4d(p: vec4<f32>) -> f32 {
    var i = floor(p);
    var f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    
    let n000 = hash3(i.xyz);
    let n100 = hash3(i.xyz + vec3<f32>(1.0, 0.0, 0.0));
    let n010 = hash3(i.xyz + vec3<f32>(0.0, 1.0, 0.0));
    let n110 = hash3(i.xyz + vec3<f32>(1.0, 1.0, 0.0));
    let n001 = hash3(i.xyz + vec3<f32>(0.0, 0.0, 1.0));
    let n101 = hash3(i.xyz + vec3<f32>(1.0, 0.0, 1.0));
    let n011 = hash3(i.xyz + vec3<f32>(0.0, 1.0, 1.0));
    let n111 = hash3(i.xyz + vec3<f32>(1.0, 1.0, 1.0));
    
    let nx00 = mix(n000, n100, u.x);
    let nx10 = mix(n010, n110, u.x);
    let nx01 = mix(n001, n101, u.x);
    let nx11 = mix(n011, n111, u.x);
    
    let nxy0 = mix(nx00, nx10, u.y);
    let nxy1 = mix(nx01, nx11, u.y);
    
    return mix(nxy0, nxy1, u.z);
}

fn fbm(p: vec2<f32>, time: f32, octaves: i32) -> f32 {
    var value = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amp * (hash3(vec3<f32>(p * freq, time * (1.0 + f32(i) * 0.2))) - 0.5);
        freq = freq * 2.15;
        amp = amp * 0.55;
    }
    return value;
}

fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
    let eps = 0.01;
    let n1 = fbm(p + vec2<f32>(eps, 0.0), time, 4);
    let n2 = fbm(p + vec2<f32>(0.0, eps), time, 4);
    let n3 = fbm(p - vec2<f32>(eps, 0.0), time, 4);
    let n4 = fbm(p - vec2<f32>(0.0, eps), time, 4);
    return vec2<f32>((n2 - n4) / (2.0 * eps), (n1 - n3) / (2.0 * eps));
}

fn voronoi(p: vec2<f32>, time: f32) -> vec3<f32> {
    var i = floor(p);
    var f = fract(p);
    var minDist1 = 1000.0;
    var minDist2 = 1000.0;
    var minPoint = vec2<f32>(0.0);
    
    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let seed = hash3(vec3<f32>(i + neighbor, time * 0.1)) * 2.0 - 1.0;
            let point = neighbor + vec2<f32>(seed, seed * 0.7);
            let dist = length(point - f);
            
            let isCloser = f32(dist < minDist1);
            let isSecond = f32(dist < minDist2) * (1.0 - isCloser);
            
            minDist2 = mix(minDist2, minDist1, isCloser);
            minDist2 = mix(minDist2, dist, isSecond);
            minDist1 = mix(minDist1, dist, isCloser);
            minPoint = mix(minPoint, vec2<f32>(seed, seed), isCloser);
        }
    }
    return vec3<f32>(minDist1, minDist2, minPoint.x);
}

fn quaternionRotate(color: vec3<f32>, angle: f32, axis: vec3<f32>) -> vec3<f32> {
    let c = cos(angle);
    let s = sin(angle);
    let oneMinusC = 1.0 - c;
    let ax = normalize(axis);
    
    let xy = ax.x * ax.y * oneMinusC;
    let xz = ax.x * ax.z * oneMinusC;
    let yz = ax.y * ax.z * oneMinusC;
    let xs = ax.x * s;
    let ys = ax.y * s;
    let zs = ax.z * s;
    
    let m00 = ax.x * ax.x * oneMinusC + c;
    let m01 = xy + zs;
    let m02 = xz - ys;
    let m10 = xy - zs;
    let m11 = ax.y * ax.y * oneMinusC + c;
    let m12 = yz + xs;
    let m20 = xz + ys;
    let m21 = yz - xs;
    let m22 = ax.z * ax.z * oneMinusC + c;
    
    return vec3<f32>(
        color.x * m00 + color.y * m10 + color.z * m20,
        color.x * m01 + color.y * m11 + color.z * m21,
        color.x * m02 + color.y * m12 + color.z * m22
    );
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    let f = fract(h6);
    let x = c * (1.0 - abs(f * 2.0 - 1.0));
    let i = u32(h6) % 6u;
    var rgb = vec3<f32>(0.0);
    rgb = mix(rgb, vec3<f32>(c, x, 0.0), f32(i == 0u));
    rgb = mix(rgb, vec3<f32>(x, c, 0.0), f32(i == 1u));
    rgb = mix(rgb, vec3<f32>(0.0, c, x), f32(i == 2u));
    rgb = mix(rgb, vec3<f32>(0.0, x, c), f32(i == 3u));
    rgb = mix(rgb, vec3<f32>(x, 0.0, c), f32(i == 4u));
    rgb = mix(rgb, vec3<f32>(c, 0.0, x), f32(i == 5u));
    return rgb + vec3<f32>(v - c);
}

fn spectralPower(color: vec3<f32>, pattern: f32) -> vec3<f32> {
    let safeColor = max(color, vec3<f32>(0.001));
    let highPass = pow(safeColor, vec3<f32>(2.0));
    let lowPass = sqrt(safeColor);
    let bandPass = sin(safeColor * 3.14159);
    return mix(lowPass, highPass, pattern) + bandPass * pattern * 0.1;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let dims = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / dims;
    let texel = 1.0 / dims;
    let time = u.config.x;
    
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let globalIntensity = clamp(0.4 + bass * 0.6, 0.0, 1.0);
    
    let foamScale = u.zoom_params.x * 3.0 + 1.0;
    let flowSpeed = u.zoom_params.y;
    let diffusionRate = u.zoom_params.z * 0.9;
    let octaveCount = i32(u.zoom_params.w * 4.0 + 3.0);
    let rotationSpeed = u.zoom_config.x * 2.0;
    let depthParallax = u.zoom_config.y * 0.2;
    let emissionThreshold = u.zoom_config.z * 0.5 + 0.3;
    let chromaticSpread = u.zoom_config.w * 2.0 + 0.5;
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let srcColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    
    let curl = curlNoise(uv * foamScale * 0.5, time * flowSpeed);
    
    var totalWarp = vec2<f32>(0.0);
    var parallaxWeight = 0.0;
    
    for (var layer: i32 = 0; layer < 3; layer = layer + 1) {
        let layerDepth = f32(layer) * 0.33;
        let layerVelocity = 1.0 + f32(layer) * 0.5;
        let layerWeight = 1.0 / (1.0 + abs(depth - layerDepth) * 15.0);
        
        let advectedCurl = curlNoise(uv * foamScale * 0.5 + curl * layerVelocity, time * flowSpeed);
        let layerAngle = time * flowSpeed * layerVelocity + f32(layer) * 2.094;
        let layerOffset = advectedCurl * depthParallax * layerWeight + vec2<f32>(cos(layerAngle), sin(layerAngle)) * layerWeight * 0.1;
        
        let layerUV = uv + layerOffset;
        let layerNoise = fbm(layerUV * foamScale, time * layerVelocity, octaveCount);
        
        totalWarp = totalWarp + vec2<f32>(layerNoise * layerWeight * layerVelocity);
        parallaxWeight = parallaxWeight + layerWeight;
    }
    
    totalWarp = totalWarp / max(parallaxWeight, 0.001);
    totalWarp = totalWarp + curl * 0.05;
    
    let cell = voronoi(uv * foamScale + totalWarp * 2.0, time);
    let cellPattern = 1.0 - smoothstep(0.0, 0.08, cell.x);
    let cellBoundary = smoothstep(0.08, 0.12, cell.y - cell.x);
    let cellInterior = fbm(uv * foamScale * 5.0 + cell.z * 2.0, time, max(octaveCount - 2, 2));
    let hybridPattern = mix(cellInterior, cellPattern, cellBoundary);
    
    let hyperNoise = noise4d(vec4<f32>(uv * foamScale * 2.0, time * 0.3, time * 0.1));
    
    let wave1 = sin(length(uv - 0.5) * 25.0 - time * 4.0);
    let wave2 = sin(atan2(uv.y - 0.5, uv.x - 0.5) * 18.0 + time * 3.0);
    let wave3 = sin(dot(uv - 0.5, vec2<f32>(1.0, 1.0)) * 30.0 - time * 5.0);
    let interference = (wave1 * wave2 * wave3 + 1.0) * 0.5;
    
    let depthWeight = 1.0 + (1.0 - depth) * 2.0;
    let pattern = (hybridPattern * 0.4 + interference * 0.3 + hyperNoise * 0.3) * depthWeight;
    
    let luminance = dot(srcColor, vec3<f32>(0.2126, 0.7152, 0.0722));
    let rotationAxis = normalize(srcColor + vec3<f32>(0.1, 0.2, 0.3));
    let rotatedColor = quaternionRotate(srcColor, time * rotationSpeed + pattern * 3.0, rotationAxis);
    
    let dispersion = pattern * chromaticSpread * texel * 30.0;
    let depthDispersion = depth * dispersion;
    let rUV = clamp(uv + totalWarp * dispersion + depthDispersion + curl * 0.02, vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv + totalWarp * dispersion * 0.9 + curl * 0.01, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv + totalWarp * dispersion * 1.1 - depthDispersion - curl * 0.015, vec2<f32>(0.0), vec2<f32>(1.0));
    
    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    let dispersedColor = vec3<f32>(r, g, b);
    
    let emission = smoothstep(emissionThreshold, 1.0, cellBoundary * pattern * luminance);
    let plasmaColor = hsv2rgb(fract(time * 0.05 + pattern + cell.z), 0.9, 1.0);
    let emissiveColor = mix(dispersedColor, plasmaColor, emission * 0.5);
    
    let historyUV = clamp(uv + totalWarp * 0.3, vec2<f32>(0.0), vec2<f32>(1.0));
    let history = textureSampleLevel(dataTextureC, u_sampler, historyUV, 0.0).rgb;
    let flowDirection = normalize(totalWarp + curl + vec2<f32>(0.001));
    let anisotropicFactor = 1.0 - abs(dot(flowDirection, normalize(uv - 0.5 + vec2<f32>(0.001)))) * 0.3;
    let anisotropicBlend = mix(emissiveColor, history, diffusionRate * anisotropicFactor);
    
    let spectralColor = spectralPower(anisotropicBlend, pattern);
    
    let finalColor = mix(srcColor, spectralColor, globalIntensity);
    
    let lumaOut = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
    let alphaOut = clamp(0.4 + lumaOut * 0.3 + globalIntensity * 0.3 + bass * 0.1, 0.0, 1.0);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alphaOut));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(finalColor, alphaOut));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
