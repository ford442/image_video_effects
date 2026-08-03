// ═══════════════════════════════════════════════════════════════════
//  Graviton Plasma-Lotus
//  Category: generative
//  Features: generative, mouse-driven, audio-reactive, temporal, depth-aware, upgraded-rgba
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
    zoom_params: vec4<f32>,  // x=Rotation Speed, y=Complexity, z=Bloom Intensity, w=Gravity Well Strength
    ripples: array<vec4<f32>, 50>,
};


// Helper: 3D Rotation Matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x*(a*x+b))/(x*(c*x+d)+e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// KIFS Fold
fn fold(p: vec3<f32>, time: f32) -> vec3<f32> {
    var q = p;
    for(var i = 0; i < 4; i++) {
        q = abs(q) - 0.5;
        // Apply rotation
        let r = rot(time * 0.1 + f32(i));
        let q_xy = r * q.xy;
        q.x = q_xy.x;
        q.y = q_xy.y;
        let q_yz = r * q.yz;
        q.y = q_yz.x;
        q.z = q_yz.y;
    }
    return q;
}

// Signed Distance Field
fn map(p: vec3<f32>) -> vec2<f32> {
    let time = u.config.x * u.zoom_params.x; // Speed param

    // Domain warp
    var q = p;
    q.x += sin(q.z * 2.0 + time) * 0.2;
    q.y += cos(q.x * 2.0 + time) * 0.2;

    // KIFS structure
    let folded_q = fold(q, time);

    // Base lotus petal (distorted sphere)
    let d1 = length(folded_q) - 0.3 * u.zoom_params.y; // Size/complexity param

    // Central Core
    let d2 = length(p) - 0.5;

    // Smooth-min blend
    let k = 0.5;
    let h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
    let d = mix(d2, d1, h) - k * h * (1.0 - h);

    var mat = 1.0;
    if (d1 < d2) { mat = 2.0; } // 1.0 = Core, 2.0 = Petals

    return vec2<f32>(d, mat);
}

// Raymarching
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    var dO = 0.0;
    var mat = 0.0;
    for(var i = 0; i < 80; i++) {
        let p = ro + rd * dO;
        let dS = map(p);
        dO += max(dS.x * 0.85, 0.002);
        mat = dS.y;
        if(dO > 30.0 || abs(dS.x) < 0.001) { break; }
    }
    return vec2<f32>(dO, mat);
}

// Normal Calculation
fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p).x;
    let n = d - vec3<f32>(
        map(p - e.xyy).x,
        map(p - e.yxy).x,
        map(p - e.yyx).x
    );
    return normalize(n);
}

// --- Main Compute ---
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let uv = (vec2<f32>(id.xy) * 2.0 - res) / res.y;

    if (f32(id.x) >= res.x || f32(id.y) >= res.y) { return; }

    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    var mouseUv = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var mouseVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) { mouseUv = rawMouse; mouseVelocity = vec2<f32>(0.0); }
    let springDt = select(0.016, clamp(u.config.x - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
    let springOmega = 8.0;
    mouseVelocity += ((rawMouse - mouseUv) * springOmega * springOmega - mouseVelocity * 2.0 * springOmega) * springDt;
    mouseUv += mouseVelocity * springDt;
    if (id.x == 0u && id.y == 0u && arrayLength(&extraBuffer) > 138u) {
        extraBuffer[133] = mouseUv.x; extraBuffer[134] = mouseUv.y;
        extraBuffer[135] = mouseVelocity.x; extraBuffer[136] = mouseVelocity.y;
        extraBuffer[137] = 1.0; extraBuffer[138] = u.config.x;
    }

    // Mouse Interaction (Gravity Well Distortion), normalized and aspect-correct.
    let mouse = (mouseUv - vec2<f32>(0.5)) * vec2<f32>(2.0 * res.x / res.y, 2.0);
    var rd_uv = uv;
    let dist_to_mouse = length(uv - mouse);
    let gravity_strength = u.zoom_params.w;
    rd_uv += (mouse - uv) / max(dist_to_mouse, 0.001) * (gravity_strength / (dist_to_mouse * 10.0 + 1.0));

    let uv01 = (vec2<f32>(id.xy) + vec2<f32>(0.5)) / res;
    var clickGravity = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = u.config.x - ripple.z;
        if (age >= 0.0 && age < 2.0) {
            let radius = length((uv01 - ripple.xy) * vec2<f32>(res.x / res.y, 1.0));
            clickGravity = max(clickGravity, exp(-abs(radius - age * 0.2) * 65.0) * exp(-age * 1.5));
        }
    }
    rd_uv += normalize(uv + vec2<f32>(0.0001)) * clickGravity * 0.08;

    let ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(rd_uv, 1.0));

    let rm = raymarch(ro, rd);
    let d = rm.x;
    let mat = rm.y;

    var col = vec3<f32>(0.0);

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    if (d < 30.0) {
        let p = ro + rd * d;
        let n = getNormal(p);

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let viewDir = normalize(-rd);
        let rim = 1.0 - max(dot(viewDir, n), 0.0);

        // Color mapping
        let time = u.config.x;
        let baseColor = 0.5 + 0.5 * cos(time + p.xyx + vec3<f32>(0.0, 2.0, 4.0));

        if (mat == 1.0) {
            // Core: Audio reactive glow
            col = vec3<f32>(1.0, 0.3, 0.8) * (1.0 + bass * 1.5) * diff + vec3<f32>(0.8, 0.1, 0.4) * rim;
        } else if (mat == 2.0) {
            // Petals: Iridescent subsurface
            col = baseColor * diff * (1.0 + mids * 0.3) + vec3<f32>(0.2, 0.6, 1.0) * smoothstep(0.6, 1.0, rim) * (1.0 + treble * 0.4);
        }

        // Apply Bloom
        col += vec3<f32>(1.0, 0.5, 0.8) * (0.12 + rim * 0.35) * u.zoom_params.z;

    } else {
        col = vec3<f32>(0.01, 0.01, 0.03); // Deep space background
    }

    col += vec3<f32>(0.4, 0.7, 1.3) * clickGravity * (0.45 + treble * 0.25);
    let prev = textureLoad(dataTextureC, vec2<i32>(id.xy), 0);
    col = mix(col, prev.rgb * 0.9, clamp(0.025 + bass * 0.01, 0.0, 0.07));
    col = acesToneMap(max(col, vec3<f32>(0.0)));
    let _luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let hit = d < 30.0;
    let _alpha = clamp(select(0.0, 0.35, hit) + _luma * 0.55 + clickGravity * 0.25, 0.0, 0.97);
    let outColor = vec4<f32>(col, _alpha);
    textureStore(writeTexture, vec2<i32>(id.xy), outColor);
    let _depth = select(0.0, clamp(1.0-d/30.0, 0.0, 1.0), hit);
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(_depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(id.xy), outColor);
}
