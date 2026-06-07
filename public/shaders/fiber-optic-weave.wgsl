// ═══════════════════════════════════════════════════════════════════
//  Fiber Optic Weave
//  Category: image
//  Features: woven-fibers, mouse-pluck, audio-reactive, signal-pulse, upgraded-rgba
//  Complexity: Medium
//  Phase B / Interactivist
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Density, y=Glow, z=Force, w=Fray
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;
const PHI: f32 = 1.61803398874989484820;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / max(resolution.y, 1.0);

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params — bass amplifies fiber pulse
    let density = u.zoom_params.x * 100.0 + 10.0;
    let glow = u.zoom_params.y * (1.0 + bass * 0.4);
    let force = u.zoom_params.z;
    let fray = u.zoom_params.w;

    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Fiber strips
    let stripIndex = floor(uv.y * density);
    let stripUV = fract(uv.y * density);
    let isOdd = (stripIndex % 2.0) >= 1.0;

    // Mouse pluck — close to fiber centerline = pluck wave (golden-ratio harmonic per fiber)
    let stripCenter = (stripIndex + 0.5) / density;
    let dy = abs(uv.y - stripCenter);
    let dxToMouse = abs(uv.x - mouse.x);
    let yToMouseStrip = abs(stripIndex - floor(mouse.y * density));
    let pluckGate = step(yToMouseStrip, 1.5);  // pluck nearby strips
    let pluck = exp(-dxToMouse * 5.0) * pluckGate * (mouseDown * 0.6 + 0.2);

    // Weaving displacement (alternating, with bass-driven sin wave)
    let weavePhase = uv.y * 20.0 + time * 2.0 * (1.0 + bass * 0.3) + stripIndex * PHI;
    let weaveAmt = sin(weavePhase) * 0.005 * fray;
    var offsetX = select(-weaveAmt, weaveAmt, isOdd);
    offsetX += pluck * sin((uv.x - mouse.x) * 50.0 + time * 8.0) * 0.02;

    // Mouse repulsion (force param)
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dM = length(distVec);
    let repulsionStr = exp(-dM * dM * 12.0) * force * 0.2;
    let dir = distVec / max(dM, 1e-4);
    offsetX += dir.x * repulsionStr;

    let finalUV = clamp(vec2<f32>(uv.x + offsetX, uv.y), vec2<f32>(0.0), vec2<f32>(1.0));
    var col = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    // Fiber edge glow (pseudo cylindrical lighting)
    let edge = abs(stripUV - 0.5) * 2.0;
    let glowFactor = smoothstep(0.7, 1.0, edge) * glow;
    let lum = dot(col.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Signal pulse traveling along fiber — palette-mapped, golden-spaced per strip
    let pulsePos = fract(time * 0.4 + stripIndex * (PHI - 1.0));
    let pulseDist = abs(uv.x - pulsePos);
    let pulseGlow = exp(-pulseDist * 30.0) * (0.4 + bass * 0.6);
    let palIdx = u32(clamp((stripIndex / density + time * 0.05) * 255.0, 0.0, 255.0));
    let pulseColor = plasmaBuffer[palIdx % 256u].rgb;

    // Add fiber glow + signal pulse + cyan tint baseline
    let glowColor = vec3<f32>(0.2, 0.8, 1.0) * glowFactor * lum
                  + pulseColor * pulseGlow * glow;
    col = vec4<f32>(col.rgb + glowColor, col.a);

    // Semantic alpha: glow + pluck + signal pulse drive fiber compositing weight
    let alpha = clamp(0.5 + glowFactor * 0.3 + pulseGlow * 0.4 + pluck * 0.2 + lum * 0.1, 0.0, 1.0);

    let finalRGB = col.rgb;

    textureStore(writeTexture, coord, vec4<f32>(finalRGB, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(finalRGB, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
