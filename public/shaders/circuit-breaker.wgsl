// ═══════════════════════════════════════════════════════════════════
//  Circuit Breaker
//  Category: effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let coord = vec2<i32>(global_id.xy);
    let uv    = vec2<f32>(global_id.xy) / resolution;
    let time  = u.config.x;

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Parameters
    let gridScale     = mix(20.0, 100.0, u.zoom_params.x);
    let intensity     = u.zoom_params.y;
    let jitterStrength = u.zoom_params.z;
    let edgeThreshold = u.zoom_params.w;

    // Mouse interaction
    let mouse        = u.zoom_config.yz;
    let aspectRatio  = resolution.x / max(resolution.y, 0.001);
    let uv_corrected = vec2<f32>(uv.x * aspectRatio, uv.y);
    let mouse_corrected = vec2<f32>(mouse.x * aspectRatio, mouse.y);
    let dist         = distance(uv_corrected, mouse_corrected);

    let hasMouse = step(0.001, mouse.x + mouse.y);
    // Bass boosts influence radius and strength
    let baseInfluence = smoothstep(0.4, 0.0, dist) * hasMouse * (1.0 + intensity * 2.0);
    let influence     = baseInfluence * (1.0 + bass * 0.5);

    // Grid generation
    let gridUV  = uv * gridScale;
    let gridID  = floor(gridUV);
    let gridLine = smoothstep(0.95, 1.0, fract(gridUV.x)) + smoothstep(0.95, 1.0, fract(gridUV.y));
    let isGrid  = clamp(gridLine, 0.0, 1.0);

    // Circuit nodes
    let node = step(0.9, hash21(gridID));

    // Branchless jitter: apply displacement proportional to influence, clamped to [0,1]
    let jitterActive = step(0.001, influence);
    let jitter = (vec2<f32>(hash21(uv + time), hash21(uv + time + 10.0)) - 0.5)
                 * jitterStrength * influence * 0.1 * jitterActive;
    let sampleUV = clamp(uv + jitter, vec2<f32>(0.0), vec2<f32>(1.0));

    // Sample texture
    let color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Edge detection
    let offset = 1.0 / resolution;
    let left  = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - vec2<f32>(offset.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let right = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + vec2<f32>(offset.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let up    = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - vec2<f32>(0.0, offset.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let down  = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + vec2<f32>(0.0, offset.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    let lumaWeights = vec3<f32>(0.299, 0.587, 0.114);
    let lumaL = dot(left.rgb,  lumaWeights);
    let lumaR = dot(right.rgb, lumaWeights);
    let lumaU = dot(up.rgb,    lumaWeights);
    let lumaD = dot(down.rgb,  lumaWeights);

    let edgeX = lumaL - lumaR;
    let edgeY = lumaU - lumaD;
    let edge  = sqrt(edgeX * edgeX + edgeY * edgeY);

    let isEdge = step(edgeThreshold, edge);

    // Circuit glow colors — bass tints toward overload
    let circuitColor = vec3<f32>(0.0, 0.8, 0.2);
    let overloadColor = vec3<f32>(0.5, 0.8, 1.0);
    let glow = mix(circuitColor, overloadColor, influence + bass * 0.3);

    // Branchless edge/grid blend: apply glow when isEdge or isGrid > 0.5
    let applyGlow = clamp(isEdge + isGrid, 0.0, 1.0);
    let glowBlend = 0.5 + influence * 0.5;
    let colorAfterGlow = mix(color.rgb, mix(color.rgb, glow, glowBlend), applyGlow);

    // Branchless node flash: active when influence > 0.5 AND node > 0.5
    // Treble adds sparkle to flash frequency
    let flashActive = step(0.5, influence) * node;
    let flash = sin(time * (20.0 + treble * 10.0) + hash21(gridID) * 6.28318) * 0.5 + 0.5;
    let colorAfterFlash = mix(colorAfterGlow, vec3<f32>(1.0), flash * influence * flashActive);

    // Scanline
    let scanline = sin(uv.y * resolution.y * 0.5) * 0.1;
    let finalRGB = colorAfterFlash - scanline;

    // Meaningful alpha: edge strength + grid presence + influence + bass
    let alpha = clamp(edge * 2.0 + isGrid * 0.3 + influence * 0.4 + bass * 0.2, 0.0, 1.0);

    let finalColor = vec4<f32>(finalRGB, alpha);

    textureStore(writeTexture, coord, finalColor);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, finalColor);
}
