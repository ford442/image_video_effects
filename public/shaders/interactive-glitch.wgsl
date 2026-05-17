// ═══════════════════════════════════════════════════════════════════
//  Interactive Glitch
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
    let k = vec2<f32>(
        dot(p, vec2<f32>(127.1, 311.7)),
        dot(p, vec2<f32>(269.5, 183.3))
    );
    return fract(sin(k) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params
    let intensity  = u.zoom_params.x;  // Base Glitch Intensity
    let radius     = u.zoom_params.y;  // Mouse Influence Radius
    let speed      = u.zoom_params.z;  // Glitch Speed
    let blockScale = u.zoom_params.w;  // Block Size

    // Mouse interaction
    let mouse     = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let aspect  = resolution.x / max(resolution.y, 0.001);
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist    = length(distVec);

    // Branchless influence: select(0, smoothstep(...), radius > 0)
    let rawInfluence = select(0.0, 1.0 - smoothstep(0.0, max(radius, 0.001), dist), radius > 0.0);
    // Branchless mouseDown amplification: select(1.0, 2.0, mouseDown > 0.5)
    let downMult  = select(1.0, 2.0, mouseDown > 0.5);
    let influence = rawInfluence * downMult;

    // Bass boosts totalIntensity
    let baseTotalIntensity = mix(intensity * 0.2, 1.0, influence * intensity);
    let totalIntensity     = baseTotalIntensity * (1.0 + bass * 0.5);

    // Generate glitch blocks
    let blockSize = max(0.01, blockScale * 0.2);
    let blockGrid = floor(uv / blockSize);
    let blockTime = floor(time * (speed * 10.0 + 1.0));

    let noise = hash21(blockGrid + vec2<f32>(blockTime * 0.1));

    // Branchless block offset: use step(noise, totalIntensity) as weight
    let blockActive = step(noise, totalIntensity);
    let rawShift    = (hash22(blockGrid + vec2<f32>(blockTime)) - 0.5) * 0.1 * totalIntensity;
    let offset_base = rawShift * blockActive;

    // Branchless color shift: select by hash comparison
    let colorHashVal = hash21(blockGrid + vec2<f32>(12.34));
    // Treble adds variation to the color shift amount
    let colorShiftAmt = totalIntensity * 0.05 * (1.0 + treble * 0.3);
    let colorShift    = select(0.0, colorShiftAmt, colorHashVal < 0.5) * blockActive;

    // Additional horizontal scanline tears
    let scanLine  = floor(uv.y * 50.0 + time * speed * 20.0);
    let scanNoise = hash21(vec2<f32>(scanLine, floor(time * 10.0)));
    // Branchless scanline offset: use step(scanNoise, totalIntensity * 0.5) as weight
    let scanActive   = step(scanNoise, totalIntensity * 0.5);
    let scanOffsetX  = (scanNoise - 0.5) * 0.2 * totalIntensity * scanActive;

    let finalOffset = vec2<f32>(offset_base.x + scanOffsetX, offset_base.y);

    // Apply chromatic aberration with offset
    let r = textureSampleLevel(readTexture, u_sampler, uv + finalOffset + vec2<f32>(colorShift, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv + finalOffset, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv + finalOffset - vec2<f32>(colorShift, 0.0), 0.0).b;

    // Meaningful alpha: encodes offset magnitude + totalIntensity + bass pulse
    let offsetMag  = length(finalOffset);
    let alpha      = clamp(offsetMag * 20.0 + totalIntensity * 0.5 + bass * 0.3, 0.0, 1.0);

    let finalColor = vec4<f32>(r, g, b, alpha);

    textureStore(writeTexture, coord, finalColor);
    textureStore(dataTextureA, coord, finalColor);

    // Depth passthrough
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
