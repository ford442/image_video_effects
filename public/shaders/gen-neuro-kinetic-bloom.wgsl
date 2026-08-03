// ═══════════════════════════════════════════════════════════════════
//  Neuro-Kinetic Bloom
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-08-03 (Batch 33)
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Bloom Extension, y=Repulsion Radius, z=Vein Glow, w=Camera Zoom
    ripples: array<vec4<f32>, 50>,
};

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn map(p: vec3<f32>) -> vec2<f32> {
    var pos = p;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let raw_mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let sprung_mouse = select(raw_mouse, vec2<f32>(extraBuffer[133], extraBuffer[134]), extraBuffer[137] > 0.5);
    let mouse_rot = (sprung_mouse * 2.0 - 1.0) * 3.14;

    let rot_xz = pos.xz * rot(u.config.x * 0.1 + mouse_rot.x);
    pos.x = rot_xz.x;
    pos.z = rot_xz.y;

    let rot_yz = pos.yz * rot(u.config.x * 0.05 + mouse_rot.y);
    pos.y = rot_yz.x;
    pos.z = rot_yz.y;

    // Flora Repetition
    let spacing = 6.0;
    var cell = floor(pos / spacing);
    pos = pos - spacing * round(pos / spacing);

    // Audio-reactive Twist (bass drives the writhing motion)
    let twist_amount = 0.5 + sin(u.config.x * 0.5 + bass * 6.28) * 0.2 + bass * 0.15;
    let twisted_xy = pos.xy * rot(pos.z * twist_amount);
    pos.x = twisted_xy.x;
    pos.y = twisted_xy.y;

    // Mouse Repulsion
    let mouse_pos = vec3<f32>((sprung_mouse * 2.0 - 1.0) * 10.0, 0.0);
    let dist_to_mouse = length(p - mouse_pos);
    if (dist_to_mouse < u.zoom_params.y) {
        let push = (p - mouse_pos) / max(dist_to_mouse, 0.001) * (u.zoom_params.y - dist_to_mouse) * 0.5;
        pos = pos + push;
    }

    let branch_length = 3.0 + sin(u.config.x * 0.7 + mids * 4.0) * u.zoom_params.x * (1.0 + mids * 0.4);
    let d_branch = sdCapsule(pos, vec3<f32>(0.0, 0.0, -branch_length), vec3<f32>(0.0, 0.0, branch_length), 0.3);
    let sideA = sdCapsule(pos, vec3<f32>(0.0), vec3<f32>(branch_length * 0.65, branch_length * 0.25, 0.0), 0.18);
    let sideB = sdCapsule(pos, vec3<f32>(0.0), vec3<f32>(-branch_length * 0.65, -branch_length * 0.2, 0.0), 0.18);
    let bloomBranch = min(d_branch, min(sideA, sideB));

    // Vein displacement
    let vein = sin(pos.z * 10.0 - u.config.x * 5.0) * sin(atan2(pos.y, pos.x) * 6.0);
    let final_d = bloomBranch - vein * 0.05 * u.zoom_params.z;

    return vec2<f32>(final_d * 0.5, vein); // Distance and MatID (vein intensity)
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.001;
    return normalize( e.xyy*map( p + e.xyy ).x +
                      e.yyx*map( p + e.yyx ).x +
                      e.yxy*map( p + e.yxy ).x +
                      e.xxx*map( p + e.xxx ).x );
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let dims = textureDimensions(writeTexture);
    if (coords.x >= i32(dims.x) || coords.y >= i32(dims.y)) { return; }

    // Audio reactivity: bass = bloom pulse, mids = vein growth, treble = glow sparkle
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    var mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var mouseVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) { mouse = rawMouse; mouseVelocity = vec2<f32>(0.0); }
    let springDt = select(0.016, clamp(u.config.x - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
    let springOmega = 8.0;
    mouseVelocity += ((rawMouse - mouse) * springOmega * springOmega - mouseVelocity * 2.0 * springOmega) * springDt;
    mouse += mouseVelocity * springDt;
    if (global_id.x == 0u && global_id.y == 0u && arrayLength(&extraBuffer) > 138u) {
        extraBuffer[133] = mouse.x; extraBuffer[134] = mouse.y;
        extraBuffer[135] = mouseVelocity.x; extraBuffer[136] = mouseVelocity.y;
        extraBuffer[137] = 1.0; extraBuffer[138] = u.config.x;
    }

    let uv01 = (vec2<f32>(coords) + vec2<f32>(0.5)) / vec2<f32>(dims);
    let uv = (vec2<f32>(coords) - 0.5 * vec2<f32>(dims)) / f32(dims.y);
    let ro = vec3<f32>(0.0, 0.0, -12.0 + u.zoom_params.w);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var mat_id = 0.0;
    for(var i = 0; i < 80; i++) {
        let p = ro + rd * t;
        let res = map(p);
        if(res.x < 0.001 || t > 50.0) {
            mat_id = res.y;
            break;
        }
        t += max(res.x, 0.002);
    }

    var col = vec3<f32>(0.02, 0.05, 0.1); // Deep sea void
    let hit = t < 50.0;
    var glowMass = 0.0;
    if (hit) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let lig = normalize(vec3<f32>(0.8, 0.7, -0.6));
        let dif = clamp(dot(n, lig), 0.0, 1.0);

        let baseColor = vec3<f32>(0.05, 0.1, 0.15);
        let veinColor = vec3<f32>(0.0, 1.0, 0.5) * max(0.0, mat_id) * (2.0 + mids * 3.0 + treble * 1.5);

        col = baseColor * dif + veinColor * u.zoom_params.z * (1.0 + bass * 0.5);
        col = mix(col, vec3<f32>(0.01, 0.02, 0.05), 1.0 - exp(-0.02 * t * t));
        glowMass = clamp(max(0.0, mat_id) * u.zoom_params.z + dif * 0.3, 0.0, 1.0);
    }

    var clickBloom = 0.0;
    let aspect = f32(dims.x) / f32(dims.y);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = u.config.x - ripple.z;
        if (age >= 0.0 && age < 2.0) {
            let radius = length((uv01 - ripple.xy) * vec2<f32>(aspect, 1.0));
            clickBloom = max(clickBloom, exp(-abs(radius - age * 0.18) * 65.0) * exp(-age * 1.5));
        }
    }
    col += vec3<f32>(0.08, 1.1, 0.55) * clickBloom * (0.5 + mids * 0.35);

    // Alpha encodes bloom presence: lit vein mass over the void, never flat 1.0
    let alpha = clamp(select(0.0, 0.25, hit) + glowMass + treble * 0.1 + clickBloom * 0.35, 0.0, 0.97);
    let out = vec4<f32>(acesToneMap(col * 1.1), alpha);

    // Depth: ray-march hit distance mapped to [0,1] (near = closer to camera)
    let depth = select(0.0, clamp(1.0 - t / 50.0, 0.0, 1.0), hit);
    textureStore(writeTexture, coords, out);
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coords, out);
}
