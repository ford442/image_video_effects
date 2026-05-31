// ═══════════════════════════════════════════════════════════════════
//  Color Channel Weave
//  Category: image
//  Features: audio-reactive, upgraded-rgba, semantic-alpha
//  Complexity: Medium
//  Chunks From: none
//  Created: 2026-05-30
//  Upgraded: 2026-05-31
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
  config: vec4<f32>,      // x=Time, y=ClickCount, z=ResX, w=ResY
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

    // Audio — read from plasmaBuffer[0].xyz as vec3f(bass, mids, treble)
    let audio = plasmaBuffer[0].xyz;
    let bass   = audio.x;
    let mid    = audio.y;
    let treble = audio.z;

    // Params
    let threadFreq  = mix(20.0, 120.0, u.zoom_params.x) * (1.0 + bass * 0.4);
    let weaveAngle  = mix(-0.4, 0.4,   u.zoom_params.y) + (u.zoom_config.y - 0.5) * 0.3;
    let shadowDepth = mix(0.0, 0.5,    u.zoom_params.z);
    let chromaOff   = mix(0.0, 0.008,  u.zoom_params.w) * (1.0 + treble);

    // Rotate UV for warp direction
    let cosA = cos(weaveAngle);
    let sinA = sin(weaveAngle);
    let ruv  = vec2<f32>(
        uv.x * cosA - uv.y * sinA,
        uv.x * sinA + uv.y * cosA
    );

    // Thread pattern: sine-based weave
    let warpPhase  = sin(ruv.x * threadFreq * PI) * 0.5 + 0.5; // horizontal threads
    let weftPhase  = sin(ruv.y * threadFreq * PI) * 0.5 + 0.5; // vertical threads

    // Determine which thread is on top at each pixel
    // classic over-under weave: thread alternates every half-period
    let warpCell   = floor(ruv.x * threadFreq);
    let weftCell   = floor(ruv.y * threadFreq);
    let warpOnTop  = fract((warpCell + weftCell) * 0.5) < 0.5;

    // Thread brightness from sine profile (rounded cross-section)
    let warpBright = smoothstep(0.0, 0.3, warpPhase) * smoothstep(1.0, 0.7, warpPhase);
    let weftBright = smoothstep(0.0, 0.3, weftPhase) * smoothstep(1.0, 0.7, weftPhase);
    let topBright  = select(weftBright, warpBright, warpOnTop);
    let botBright  = select(warpBright, weftBright, warpOnTop);

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
    let tinted   = mix(srcCol * weftTint, srcCol * warpTint, select(0.0, 1.0, warpOnTop));

    // Apply thread brightness and shadow
    var col = tinted * topBright * shadow;

    // Audio reactivity: mid brightens highlights
    col += srcCol * (1.0 - topBright) * 0.15 * mid;

    // Yarn specular micro-highlight
    let specMask = topBright * topBright;
    col += vec3<f32>(0.8, 0.85, 0.9) * specMask * 0.12 * (1.0 + treble * 0.5);

    col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.5));

    // Semantic alpha — use saturate for [0,1] clamping
    let alpha = saturate(srcA);

    let outColor = vec4<f32>(col, alpha);
    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(topBright, shadow, 0.0, 1.0));
    textureStore(dataTextureA, coord, outColor);
    textureStore(dataTextureB, coord, vec4<f32>(warpBright, weftBright, bass, mid));
}
