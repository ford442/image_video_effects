// ═══════════════════════════════════════════════════════════════════
//  Hyper Labyrinth — 4D Gyroid Maze
//  Category: generative
//  Features: 4d-gyroid, raymarching, spherical-mouse-orbit, neon-veins,
//            fresnel-rim, audio-reactive, bass-envelope, semantic-alpha,
//            fog-transmittance, aces-tone-map, ign-dither, depth-write
//  Complexity: High
//  Chunks From: rotate4D + 4D gyroid SDF + orbit camera (legacy
//               gen-hyper-labyrinth), bass_env / hue_preserve_clamp /
//               aces / ign (12 Kimi Graphical Tactics)
//  Upgraded: 2026-07-18
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
  config: vec4<f32>,       // x=Time, y=delta_time, zw=resolution
  zoom_config: vec4<f32>,  // x=zoom, yz=mouse_uv, w=mouse_down
  zoom_params: vec4<f32>,  // xyzw = user params p1…p4
  ripples: array<vec4<f32>, 50>,
};

// ── Kimi Graphical Tactics ─────────────────────────────────────────
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}
fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
    let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    let s = min(1.0, max_lum / max(l, 1e-4));
    return c * s;
}
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x*(a*x+b))/(x*(c*x+d)+e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

// ── 4D Rotation in XW plane ────────────────────────────────────────
fn rotate4D(p: vec4<f32>, angle: f32) -> vec4<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec4<f32>(p.x * c - p.w * s, p.y, p.z, p.x * s + p.w * c);
}

// ── Gyroid SDF (soul preserved; time4d carries the bass surge) ─────
fn map(pos3: vec3<f32>, time4d: f32) -> vec2<f32> {
    var p4 = vec4<f32>(pos3, 1.0);
    p4 = rotate4D(p4, time4d);

    // Extra YZ rotation for 3D orbiting feel
    let rotYZ = u.config.x * 0.1;
    let cy = cos(rotYZ);
    let sy = sin(rotYZ);
    let tempY = p4.y * cy - p4.z * sy;
    let tempZ = p4.y * sy + p4.z * cy;
    p4.y = tempY;
    p4.z = tempZ;

    // Gyroid-based 4D maze
    let scale = mix(1.0, 5.0, u.zoom_params.x);
    let q = p4 * scale;
    let val = sin(q.x) * cos(q.y) + sin(q.y) * cos(q.z) + sin(q.z) * cos(q.w) + sin(q.w) * cos(q.x);
    let thickness = mix(0.1, 1.2, u.zoom_params.w);
    let d = (abs(val) - thickness * 0.5) / scale;
    return vec2<f32>(d * 0.5, 1.0);
}

fn calcNormal(p: vec3<f32>, time4d: f32) -> vec3<f32> {
    let e = 0.001;
    let d = map(p, time4d).x;
    return normalize(vec3<f32>(
        map(p + vec3<f32>(e, 0.0, 0.0), time4d).x - d,
        map(p + vec3<f32>(0.0, e, 0.0), time4d).x - d,
        map(p + vec3<f32>(0.0, 0.0, e), time4d).x - d
    ));
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>, time4d: f32) -> vec2<f32> {
    var t = 0.0;
    var m = 0.0;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p, time4d);
        let d = res.x;
        if (d < 0.001 || t > 50.0) {
            if (d < 0.001) { m = res.y; }
            break;
        }
        t += d;
    }
    return vec2<f32>(t, m);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res2 = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res2.x) || pixel.y >= i32(res2.y)) { return; }

    let uv = (vec2<f32>(pixel) - 0.5 * res2) / res2.y;
    let time = u.config.x;

    // ── Audio: bass envelope via dataTextureC feedback ───────────
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let prevAudio = textureLoad(dataTextureC, pixel, 0);
    let bassEnv = bass_env(prevAudio.x, bass, 0.55, 0.10);
    let midBal  = clamp(mids * 0.5, 0.0, 1.0);
    let trebN   = clamp(treble * 0.5, 0.0, 1.5);
    textureStore(dataTextureA, pixel, vec4<f32>(bassEnv, midBal, trebN, 1.0));

    // Bass surges the 4D rotation speed
    let speed  = mix(0.1, 2.0, u.zoom_params.y) * (1.0 + bassEnv * 1.5);
    let time4d = time * speed;

    // ── Camera: spherical mouse-orbit + organic drift (preserved) ─
    let mouse = u.zoom_config.yz;
    let angleX = (mouse.x - 0.5) * 6.2832;
    let angleY = (0.5 - mouse.y) * 3.1416;
    let camDist = 8.0;
    var ro = vec3<f32>(
        camDist * cos(angleY) * sin(angleX),
        camDist * sin(angleY),
        camDist * cos(angleY) * cos(angleX)
    );
    let drift = vec3<f32>(sin(time * 0.1), cos(time * 0.15), sin(time * 0.07)) * 0.6;
    ro += drift;

    let fwd = normalize(vec3<f32>(0.0) - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), fwd));
    let up = cross(fwd, right);
    let rd = normalize(fwd + right * uv.x + up * uv.y);

    let march = raymarch(ro, rd, time4d);
    let t = march.x;
    let mat = march.y;

    var color = vec3<f32>(0.0);
    // Semantic alpha: fog transmittance — near walls opaque, deep void loose
    var alpha = 0.03;

    if (mat > 0.0) {
        let p = ro + rd * t;
        let n = calcNormal(p, time4d);

        let lightDir = normalize(vec3<f32>(0.5, 0.8, -0.5));
        let diff = max(dot(n, lightDir), 0.0);
        let amb = 0.12;

        // Dark metallic wall base (preserved)
        var surfCol = vec3<f32>(0.06, 0.05, 0.09);

        // ── Neon veins: mids slide cyan ↔ magenta ────────────────
        let glowIntensity = mix(0.6, 3.5, u.zoom_params.z) * (1.0 + bassEnv * 0.9);
        var p4 = vec4<f32>(p, 1.0);
        p4 = rotate4D(p4, time4d);
        let cy2 = cos(u.config.x * 0.1);
        let sy2 = sin(u.config.x * 0.1);
        let ty = p4.y * cy2 - p4.z * sy2;
        p4.z = p4.y * sy2 + p4.z * cy2;
        p4.y = ty;
        let q = p4 * mix(1.0, 5.0, u.zoom_params.x) * 2.0;
        let pattern = sin(q.x) * sin(q.y) * sin(q.z) * sin(q.w);

        // Bass pumps the glow pulse amplitude
        let pulse = (0.5 + 0.5 * sin(time * 2.2 + p.x * 1.3 + p.z * 0.7)) * (0.7 + bassEnv * 0.8);
        let veinT = clamp(select(0.12, 0.88, pattern > 0.0) + (midBal - 0.5) * 0.7, 0.0, 1.0);
        let glowCol = mix(vec3<f32>(0.0, 0.85, 1.0), vec3<f32>(1.0, 0.25, 0.9), veinT);
        let patternFactor = smoothstep(0.35, 0.55, abs(pattern));
        surfCol += glowCol * patternFactor * glowIntensity * pulse;

        // ── Cyber rim + treble sparkle ───────────────────────────
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        let sparkle = trebN * 0.5 * (0.5 + 0.5 * sin(dot(p, vec3<f32>(41.0, 37.0, 43.0)) + time * 18.0));
        surfCol += vec3<f32>(0.3, 0.5, 1.2) * fresnel * (2.8 + sparkle * 4.0);

        color = surfCol * (diff * 0.85 + amb);

        // Exponential fog (preserved)
        let fogAmount = 1.0 - exp(-t * 0.065);
        color = mix(color, vec3<f32>(0.008, 0.008, 0.022), fogAmount);

        // Hit confidence × fog transmittance
        alpha = clamp(exp(-t * 0.10) * 1.1, 0.06, 1.0);
    } else {
        // Deep void — composites loosely in slot 2/3
        color = vec3<f32>(0.0, 0.0, 0.045);
    }

    // ── Hue-preserving clamp → ACES → IGN dither ─────────────────
    color = hue_preserve_clamp(color, 6.0);
    color = aces(color * (1.0 + bassEnv * 0.12));
    color += vec3<f32>((ign(vec2<f32>(pixel)) - 0.5) * (1.5 / 255.0));

    // Premultiplied semantic alpha write
    textureStore(writeTexture, pixel, vec4<f32>(color * alpha, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(t / 50.0, 0.0, 0.0, 0.0));
}
