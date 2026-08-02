// ═══════════════════════════════════════════════════════════════════
//  Color Channel Weave
//  Category: image
//  Features: mouse-driven, click-reactive, audio-reactive, depth-aware, upgraded-rgba, semantic-alpha
//  Complexity: Medium
//  Upgraded: 2026-08-02 (Batch 30)
// ═══════════════════════════════════════════════════════════════════
//  Samples R, G, and B channels from offset positions, creating the
//  visual illusion of woven fabric threads. Horizontal threads carry
//  red and blue; vertical threads carry green. Audio shifts the
//  thread spacing and weave angle. Mouse tilts the warp direction.
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
  config: vec4<f32>,      // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>, // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>, // x=ThreadSpacing, y=WeaveAngle, z=ShadowDepth, w=ChromaOffset
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265358979;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims  = u.config.zw;
    if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }

    let uv    = vec2<f32>(gid.xy) / dims;
    let coord = vec2<i32>(gid.xy);
    let time  = u.config.x;

    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mid = audio.y;
    let treble = audio.z;

    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    var mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var mouseVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) {
        mouse = rawMouse;
        mouseVelocity = vec2<f32>(0.0);
    }
    let dt = select(0.016, clamp(time - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
    let omega = 8.0;
    mouseVelocity += ((rawMouse - mouse) * (omega * omega) - mouseVelocity * (2.0 * omega)) * dt;
    mouse += mouseVelocity * dt;
    if (gid.x == 0u && gid.y == 0u) {
        extraBuffer[133] = mouse.x;
        extraBuffer[134] = mouse.y;
        extraBuffer[135] = mouseVelocity.x;
        extraBuffer[136] = mouseVelocity.y;
        extraBuffer[137] = 1.0;
        extraBuffer[138] = time;
    }

    // Params
    let threadFreq  = mix(20.0, 120.0, u.zoom_params.x) * (1.0 + bass * 0.4);
    let weaveAngle  = mix(-0.4, 0.4,   u.zoom_params.y) + (mouse.x - 0.5) * 0.3;
    let shadowDepth = mix(0.0, 0.5,    u.zoom_params.z);
    let chromaOff   = mix(0.0, 0.008,  u.zoom_params.w) * (1.0 + treble);

    // Rotate UV for warp direction
    let cosA = cos(weaveAngle);
    let sinA = sin(weaveAngle);
    let ruv  = vec2<f32>(
        uv.x * cosA - uv.y * sinA,
        uv.x * sinA + uv.y * cosA
    );

    var pluck = 0.0;
    let aspect = dims.x / dims.y;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.2) {
            let radius = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
            pluck += sin(radius * 55.0 - age * 16.0) * exp(-radius * 7.0 - age * 1.4);
        }
    }
    pluck = clamp(pluck, -1.0, 1.0);

    let warpPhase  = sin(ruv.x * threadFreq * PI + pluck * 0.8) * 0.5 + 0.5;
    let weftPhase  = sin(ruv.y * threadFreq * PI - pluck * 0.8) * 0.5 + 0.5;

    // Determine which thread is on top at each pixel
    // classic over-under weave: thread alternates every half-period
    let warpCell   = floor(ruv.x * threadFreq);
    let weftCell   = floor(ruv.y * threadFreq);
    let warpOnTop  = fract((warpCell + weftCell) * 0.5) < 0.5;

    // Thread brightness from sine profile (rounded cross-section)
    let warpBright = smoothstep(0.0, 0.3, warpPhase) * (1.0 - smoothstep(0.7, 1.0, warpPhase));
    let weftBright = smoothstep(0.0, 0.3, weftPhase) * (1.0 - smoothstep(0.7, 1.0, weftPhase));
    let topBright  = select(weftBright, warpBright, warpOnTop);
    let botBright  = select(warpBright, weftBright, warpOnTop);
    let cellCode = u32(abs(warpCell * 19.0 + weftCell * 37.0));
    let fftVoice = clamp(plasmaBuffer[(cellCode % 8u) + 1u].x, 0.0, 1.0);

    // Under-thread shadow
    let shadow     = 1.0 - shadowDepth * (1.0 - botBright);

    // UV offsets per channel: warp→R, neutral→G, weft→B
    let warpDir = vec2<f32>(cosA, sinA);
    let weftDir = vec2<f32>(-sinA, cosA);
    let rUV = clamp(uv + warpDir * chromaOff,  vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv,                         vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv + weftDir * chromaOff,  vec2<f32>(0.0), vec2<f32>(1.0));

    let srcR = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let srcG = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let srcB = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    let srcA = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).a;

    // Build thread colour: warp threads tinted warm, weft tinted cool
    let warpTint = vec3<f32>(1.05, 0.97, 0.93);
    let weftTint = vec3<f32>(0.93, 0.97, 1.05);
    let srcCol   = vec3<f32>(srcR, srcG, srcB);
    let tinted   = mix(srcCol * weftTint, srcCol * warpTint, f32(select(0, 1, warpOnTop)));

    // Apply thread brightness and shadow
    var col = tinted * topBright * shadow;

    // Audio reactivity: mid brightens highlights
    col += srcCol * (1.0 - topBright) * 0.15 * mid;

    // Yarn specular micro-highlight
    let specMask = topBright * topBright;
    col += vec3<f32>(0.8, 0.85, 0.9) * specMask * 0.12 * (1.0 + treble * 0.5 + fftVoice * 0.45);

    col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.5));

    // Semantic alpha
    let alpha = clamp(srcA, 0.0, 1.0);

    let outColor = vec4<f32>(col, alpha);
    textureStore(writeTexture, coord, outColor);
    let sourceDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let weaveDepth = clamp(sourceDepth + topBright * shadowDepth * 0.18 + abs(pluck) * topBright * 0.05, 0.0, 1.0);
    textureStore(writeDepthTexture, coord, vec4<f32>(weaveDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outColor);
    textureStore(dataTextureB, coord, vec4<f32>(warpBright, weftBright, bass, mid));
}
