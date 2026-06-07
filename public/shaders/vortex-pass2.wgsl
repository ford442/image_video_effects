// ═══════════════════════════════════════════════════════════════════
//  Vortex Pass 2
//  Category: distortion
//  Features: upgraded-rgba, fluid, vortex, iridescent, audio-reactive,
//            chromatic-velocity-blur, temporal-vorticity, audio-swirl
//  Complexity: High
//  Upgraded: 2026-05-31
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

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
  return c.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let swirlStrength = u.zoom_params.x * (1.0 + bass * 0.3);
    let iridescence = u.zoom_params.y;
    let trailLength = u.zoom_params.z;
    let paletteSpeed = u.zoom_params.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let velData = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let velocity = velData.rg * 2.0 - 1.0;
    let curl = velData.b;
    let pressure = velData.a;

    let speed = length(velocity);
    let flowDir = normalize(velocity + vec2<f32>(1e-4));

    // Chromatic velocity blur offsets: RGB trail in flow direction
    let blurSteps = i32(trailLength * 5.0 + 1.0);
    var rBlur = vec3<f32>(0.0);
    var gBlur = vec3<f32>(0.0);
    var bBlur = vec3<f32>(0.0);
    for (var i: i32 = 0; i < blurSteps; i = i + 1) {
        let t = f32(i) / f32(blurSteps);
        let rOff = uv + flowDir * t * speed * 0.03 * (1.0 + treble * 0.3);
        let gOff = uv + flowDir * t * speed * 0.03;
        let bOff = uv + flowDir * t * speed * 0.03 * (1.0 - bass * 0.2);
        rBlur += textureSampleLevel(readTexture, u_sampler, clamp(rOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        gBlur += textureSampleLevel(readTexture, u_sampler, clamp(gOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        bBlur += textureSampleLevel(readTexture, u_sampler, clamp(bOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    }
    let invSteps = 1.0 / max(f32(blurSteps), 1.0);
    rBlur *= invSteps;
    gBlur *= invSteps;
    bBlur *= invSteps;

    // Iridescent vorticity tint based on curl
    let hue = fract(abs(curl) * 2.0 + time * paletteSpeed * 0.1 + depth * 0.2);
    let tint = hsv2rgb(vec3<f32>(hue, 0.7 + mids * 0.2, 0.9 + bass * 0.1));

    let vorticityIntensity = abs(curl) * 5.0;
    let vorticityColor = tint * vorticityIntensity * iridescence;

    // Temporal vorticity accumulation: previous frame mixes in for swirl persistence
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    var velocityColor = mix(vec3<f32>(rBlur.r, gBlur.g, bBlur.b), vorticityColor, clamp(vorticityIntensity, 0.0, 1.0));
    velocityColor = mix(velocityColor, prev * 0.88, 0.06 + mids * 0.02);

    // Palette grading: pressure drives brightness
    let graded = velocityColor * (0.7 + pressure * 0.6);

    let alpha = clamp(0.6 + speed * 0.4 + vorticityIntensity * 0.2, 0.0, 1.0);

    let finalColor = mix(graded, graded * (1.0 + depth * 0.2), 0.3);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0, 0, 1));
}
