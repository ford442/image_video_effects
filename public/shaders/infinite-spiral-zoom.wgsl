// ═══════════════════════════════════════════════════════════════════════════════
//  Möbius–Droste Infinite Spiral
//  Category: distortion
//  Features: mouse-driven, audio-reactive, temporal
//  Complexity: High
//  Scientific: Möbius transformation f(z)=(az+b)/(cz+d) in ℂ composed with
//              log-polar map for Droste self-similar zoom effect,
//              audio-driven rotation of Möbius parameters,
//              multi-fold rotational symmetry, chromatic ring fringing
//  Upgraded: Phase B
// ═══════════════════════════════════════════════════════════════════════════════

@group(0) @binding(0)  var u_sampler: sampler;
@group(0) @binding(1)  var readTexture: texture_2d<f32>;
@group(0) @binding(2)  var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3)  var<uniform> u: Uniforms;
@group(0) @binding(4)  var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5)  var non_filtering_sampler: sampler;
@group(0) @binding(6)  var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7)  var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8)  var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9)  var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config:      vec4<f32>,  // x=Time, y=ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
    zoom_params: vec4<f32>,  // x=ZoomSpeed, y=MobiusStrength, z=Symmetry, w=Chromatic
    ripples:     array<vec4<f32>, 50>,
}

// Complex multiply
fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x*b.x - a.y*b.y, a.x*b.y + a.y*b.x);
}
// Complex divide
fn cdiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let d = dot(b, b);
    return vec2<f32>((a.x*b.x + a.y*b.y)/d, (a.y*b.x - a.x*b.y)/d);
}

// Möbius transformation: f(z) = (a·z + b) / (c·z + d)
// a,b,c,d encoded as complex pairs
fn mobius(z: vec2<f32>, a: vec2<f32>, b: vec2<f32>, c: vec2<f32>, d: vec2<f32>) -> vec2<f32> {
    return cdiv(cmul(a, z) + b, cmul(c, z) + d);
}

// Log-polar → UV (Droste tile)
fn logPolarUV(z: vec2<f32>, zoomSpeed: f32, twist: f32, time: f32, branches: f32) -> vec2<f32> {
    let r = length(z);
    if (r < 0.0001) { return vec2<f32>(0.5); }
    var u_c = log(r) - time * zoomSpeed;
    var v_c = atan2(z.y, z.x) / 6.28318;
    v_c += u_c * twist * 0.15;
    return fract(vec2<f32>(u_c, v_c * branches));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv     = vec2<f32>(global_id.xy) / resolution;
    let time   = u.config.x;
    let aspect = resolution.x / resolution.y;
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let zoomSpeed  = (u.zoom_params.x - 0.5) * 4.0;
    let mobStrength= mix(0.0, 0.8, u.zoom_params.y);
    let branches   = floor(u.zoom_params.z * 5.0) + 1.0;
    let chromatic  = u.zoom_params.w * 0.08 + treble * 0.02;

    let mouse = u.zoom_config.yz;

    // Pixel in centered aspect-correct space
    var p = (uv - mouse) * vec2<f32>(aspect, 1.0);

    // ─── Möbius transformation ───
    // Animated parameter orbit: a = 1, b = mob·exp(iθ), c = mob·exp(-iθ), d = 1
    let theta = time * 0.4 + bass * 0.8;
    let bVec  = mobStrength * vec2<f32>(cos(theta), sin(theta));
    let cVec  = mobStrength * vec2<f32>(cos(-theta), sin(-theta));
    p = mobius(p, vec2<f32>(1.0, 0.0), bVec, cVec, vec2<f32>(1.0, 0.0));

    // ─── Log-polar Droste tiling ───
    let twist  = (mids - 0.5) * 1.5 + 0.3;
    let uvBase = logPolarUV(p, zoomSpeed, twist, time, branches);

    // Chromatic aberration via slightly offset Möbius params for R and B
    let dtheta = chromatic;
    let bR = (mobStrength + chromatic * 0.1) * vec2<f32>(cos(theta + dtheta), sin(theta + dtheta));
    let cR = (mobStrength + chromatic * 0.1) * vec2<f32>(cos(-theta - dtheta), sin(-theta - dtheta));
    var pR = (uv - mouse) * vec2<f32>(aspect, 1.0);
    pR = mobius(pR, vec2<f32>(1.0, 0.0), bR, cR, vec2<f32>(1.0, 0.0));
    let uvR = logPolarUV(pR, zoomSpeed, twist, time, branches);

    let bB = (mobStrength - chromatic * 0.1) * vec2<f32>(cos(theta - dtheta), sin(theta - dtheta));
    let cB = (mobStrength - chromatic * 0.1) * vec2<f32>(cos(-theta + dtheta), sin(-theta + dtheta));
    var pB = (uv - mouse) * vec2<f32>(aspect, 1.0);
    pB = mobius(pB, vec2<f32>(1.0, 0.0), bB, cB, vec2<f32>(1.0, 0.0));
    let uvB = logPolarUV(pB, zoomSpeed, twist, time, branches);

    let sR  = textureSampleLevel(readTexture, u_sampler, uvR,   0.0);
    let sG  = textureSampleLevel(readTexture, u_sampler, uvBase, 0.0);
    let sB2 = textureSampleLevel(readTexture, u_sampler, uvB,   0.0);
    let color = vec3<f32>(sR.r, sG.g, sB2.b);

    // Tile-seam edge glow (interference rings at tiling boundaries)
    let fx = fract(uvBase.x * 8.0);
    let fy = fract(uvBase.y * 8.0);
    let edgeGlow = smoothstep(0.48, 0.5, fx) * smoothstep(0.48, 0.5, fy) * 0.3 * treble;
    let finalColor = color + vec3<f32>(0.6, 0.3, 1.0) * edgeGlow;

    let dep = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(uvBase, length(p), mobStrength));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(dep, 0.0, 0.0, 0.0));
}
