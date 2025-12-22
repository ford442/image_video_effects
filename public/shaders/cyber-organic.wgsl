// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Utils
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(dot(hash22(i + vec2<f32>(0.0, 0.0)), f - vec2<f32>(0.0, 0.0)),
                   dot(hash22(i + vec2<f32>(1.0, 0.0)), f - vec2<f32>(1.0, 0.0)), u.x),
               mix(dot(hash22(i + vec2<f32>(0.0, 1.0)), f - vec2<f32>(0.0, 1.0)),
                   dot(hash22(i + vec2<f32>(1.0, 1.0)), f - vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var val = 0.0;
    var amp = 0.5;
    var pos = p;
    for (var i = 0; i < 4; i++) {
        val += amp * noise(pos);
        pos = pos * 2.0;
        amp *= 0.5;
    }
    return val + 0.5;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    // Params
    let scanSpeed = u.zoom_params.x * 2.0;
    let organicScale = mix(5.0, 20.0, u.zoom_params.y);
    let revealRadius = u.zoom_params.z * 0.5;
    let pulseSpeed = u.zoom_params.w * 5.0;

    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);

    // Base Image
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Organic Layer Generation
    // Distort UVs with FBM
    let warp = vec2<f32>(
        fbm(uv * organicScale + vec2<f32>(time * 0.1, 0.0)),
        fbm(uv * organicScale + vec2<f32>(0.0, time * 0.1))
    );
    let organicUV = uv + (warp - 0.5) * 0.1;
    let organicTex = textureSampleLevel(readTexture, u_sampler, organicUV, 0.0);

    // Shift colors to look "organic/alien" (invert + hue shift)
    var organicColor = vec4<f32>(organicTex.g, organicTex.b, organicTex.r, 1.0);
    organicColor = mix(organicColor, vec4<f32>(0.8, 0.2, 0.6, 1.0), 0.3); // Purple tint

    // Add pulsing veins
    let vein = smoothstep(0.4, 0.6, abs(fbm(uv * organicScale * 2.0 + time * 0.2) - 0.5));
    organicColor += vec4<f32>(vein * sin(time * pulseSpeed) * 0.5, 0.0, 0.0, 0.0);

    // Masks
    // 1. Mouse Reveal
    let mouseUV = mouse;
    // Correct for aspect ratio for circle
    let distVec = (uv - mouseUV) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    let mouseMask = smoothstep(revealRadius, revealRadius * 0.8, dist);

    // 2. Scanner Beam
    let scanPos = fract(time * scanSpeed * 0.2);
    let scanDist = abs(uv.x - scanPos);
    let scanMask = smoothstep(0.05, 0.0, scanDist) * 0.5; // Fades out
    // Add vertical noise to scan line
    let scanNoise = noise(vec2<f32>(uv.y * 50.0, time * 10.0));
    let finalScanMask = scanMask * step(0.2, scanNoise);

    // Combine Masks
    let reveal = clamp(mouseMask + finalScanMask, 0.0, 1.0);

    // Digital grid overlay on the reveal edge
    let grid = step(0.98, fract(uv.x * 50.0)) + step(0.98, fract(uv.y * 50.0 * aspect));
    let edge = smoothstep(0.0, 0.1, abs(reveal - 0.5)) * (1.0 - abs(reveal - 0.5) * 2.0); // Peak at 0.5
    let gridOverlay = grid * edge * vec4<f32>(0.0, 1.0, 0.5, 1.0); // Cyan grid

    // Final Mix
    var finalColor = mix(baseColor, organicColor, reveal);
    finalColor += gridOverlay;

    textureStore(writeTexture, global_id.xy, finalColor);

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
