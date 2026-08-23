// ═══════════════════════════════════════════════════════════════════
//  Infinite Fractal Feedback HDR
//  Category: advanced-hybrid
//  Features: fractal-feedback, HDR-bloom, accumulative-alpha, temporal
//  Complexity: Very High
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

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hue2rgb(hue: f32) -> vec3<f32> {
    let h = fract(hue) * 6.0;
    let r = abs(h - 3.0) - 1.0;
    let g = 2.0 - abs(h - 2.0);
    let b = 2.0 - abs(h - 4.0);
    return clamp(vec3<f32>(r, g, b), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let dt = 0.016;
    let time = u.config.x;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;

    // Persistent state strictly in extraBuffer[133..138] (single-writer)
    if (gid.x == 0u && gid.y == 0u) {
        var pX = extraBuffer[133];
        var pY = extraBuffer[134];
        var vX = extraBuffer[135];
        var vY = extraBuffer[136];
        var tX = extraBuffer[137];
        var tY = extraBuffer[138];

        let mouseDown = u.zoom_config.w;
        let mousePos = u.zoom_config.yz;

        if (mouseDown > 0.0) {
            tX = mousePos.x;
            tY = mousePos.y;
        } else {
            tX = 0.5 + sin(time * 0.5) * 0.3 * cos(time * 0.31);
            tY = 0.5 + cos(time * 0.43) * 0.3 * sin(time * 0.29);
        }

        let spring = 180.0;
        let damp = 12.0;
        vX += (tX - pX) * spring * dt - vX * damp * dt;
        vY += (tY - pY) * spring * dt - vY * damp * dt;

        pX = clamp(pX + vX * dt, 0.0, 1.0);
        pY = clamp(pY + vY * dt, 0.0, 1.0);

        extraBuffer[133] = pX;
        extraBuffer[134] = pY;
        extraBuffer[135] = vX;
        extraBuffer[136] = vY;
        extraBuffer[137] = tX;
        extraBuffer[138] = tY;
    }

    // Use bounded spring coords
    let focalPoint = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    
    // Truthful three-band audio
    let bass = plasmaBuffer[0].x;
    let mid = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    
    var binSum = 0.0;
    for (var i = 1u; i < 9u; i = i + 1u) {
        binSum += plasmaBuffer[i].x;
    }
    let audioEnv = (bass + mid + treble) * 0.33 + binSum * 0.1;

    // Parameters
    let zoomRate = u.zoom_params.x;
    let spiralTightness = u.zoom_params.y;
    let colorShift = u.zoom_params.z;
    let feedbackStrength = u.zoom_params.w;

    // Continuous geometry & fractal coordinate transform
    let centered = uv - focalPoint;
    var polar = vec2<f32>(length(centered), atan2(centered.y, centered.x));
    
    let twist = sin(polar.x * 10.0 - time + audioEnv) * 0.05 * spiralTightness;
    polar.y += twist + time * 0.2 * zoomRate;
    polar.x = fract(polar.x * (1.0 - zoomRate * 0.5) - time * 0.1 * bass);
    
    let kSymmetry = 6.0;
    polar.y = (polar.y * kSymmetry) % (3.14159 * 2.0) / kSymmetry;

    let sampleUV = focalPoint + vec2<f32>(cos(polar.y), sin(polar.y)) * polar.x;
    
    // Exact textureLoad from dataTextureC
    let prev = textureLoad(dataTextureC, coord, 0);

    // Capped click fronts
    let rippleCount = min(u32(u.config.y), 50u);
    var rippleIntensity = 0.0;
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rip = u.ripples[i];
        let rDist = length(uv - rip.xy);
        let age = time - rip.z;
        if (age > 0.0 && age < 3.0) {
            let front = smoothstep(0.03, 0.0, abs(rDist - age * 0.4));
            rippleIntensity += front * max(0.0, 1.0 - age * 0.33);
        }
    }
    rippleIntensity = min(rippleIntensity, 1.5);
    
    // Optical dispersion & sampling
    let aberration = 0.005 * (1.0 + treble * 2.0);
    let rSample = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(aberration, 0.0), 0.0).r;
    let gSample = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
    let bSample = textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(aberration, 0.0), 0.0).b;
    
    var color = vec3<f32>(rSample, gSample, bSample);
    
    // Geometry injection
    let geo = smoothstep(0.1, 0.0, abs(polar.x - 0.5)) * smoothstep(0.5, 0.4, length(centered));
    let baseColor = hue2rgb(polar.y + time * 0.1 + colorShift + mid);
    color += baseColor * geo * (0.5 + bass * 0.5);
    color += rippleIntensity * vec3<f32>(1.0, 0.8, 1.2);
    
    // Temporal feedback blend
    color = mix(color, prev.rgb, feedbackStrength * 0.95);
    
    // HDR Bloom approximation & ACES
    let lum = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let bloom = color * smoothstep(0.8, 1.5, lum) * 0.5;
    let hdrColor = color + bloom;
    
    let finalColor = toneMapACES(hdrColor);
    
    // Semantic alpha
    let finalAlpha = clamp(lum * 1.5 + rippleIntensity, 0.0, 1.0);
    
    let outValue = vec4<f32>(finalColor, finalAlpha);

    // Write ONLY to dataTextureA and writeTexture
    textureStore(dataTextureA, coord, outValue);
    textureStore(writeTexture, coord, outValue);
    
    // Optional Depth write
    textureStore(writeDepthTexture, coord, vec4<f32>(polar.x, 0.0, 0.0, 0.0));
}
