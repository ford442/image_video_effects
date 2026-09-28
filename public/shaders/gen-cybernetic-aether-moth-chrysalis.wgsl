// ═══════════════════════════════════════════════════════════════════
//  Cybernetic Aether-Moth Chrysalis
//  Category: generative
//  Features: audio-reactive, upgraded-rgba, mouse-driven, click-reactive, held-drag, raymarched, depth-aware
//  Complexity: High
//  Upgraded: 2026-09-28
//  Ideas: eclosion seam (smin-lipped dorsal split); cremaster thread + silk girdle pendulum sway; defensive click wriggle
//  A packing: raw HDR display RGB + semantic alpha (C read back as colour history)
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
    config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY (0 = top), w=Held
    zoom_params: vec4<f32>,  // x=Chrysalis Complexity, y=Rotation Speed, z=Shell Hole Width, w=Color Shift
    ripples: array<vec4<f32>, 50>,
};

// Scene layout (world units). The camera sees half-height 4 at z=0, the HEAD spindle spans +-5.9 body
// units, so the body is scaled to +-2.95 and hung slightly low to leave the upper frame for the thread.
const BODY_SCALE: f32 = 0.5;
const BODY_Y: f32 = -0.45;
const ANCHOR_Y: f32 = 4.9;      // cremaster anchor, just above the top edge of the frame
const TIP_Y: f32 = 5.55;        // body-unit height where the silk leaves the shell tip

// Per-pixel-uniform pose, built once in main() and shared by map(), getNormal() and shading.
struct Pose {
    yaw: mat2x2<f32>,     // mouse orbit around the hanging axis
    pitch: mat2x2<f32>,   // mouse camera elevation
    swayX: mat2x2<f32>,   // idea 2: lateral pendulum sway about the anchor
    swayZ: mat2x2<f32>,   // idea 2: fore-aft pendulum sway about the anchor
    spin: f32,            // Rotation Speed: spin about the body's long axis
    twist: f32,           // idea 3: wriggle twist (rad at the free tip)
    gape: f32,            // idea 1: seam half-width (body units)
    pad: f32,
};

// ----------------------------------------------------------------
// Helper Functions
// ----------------------------------------------------------------
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + 33.33);
    return fract((q.xxy + q.yxx) * q.zyx);
}

// 3D Voronoi Distance
fn voronoi(x: vec3<f32>) -> vec2<f32> {
    let n = floor(x);
    let f = fract(x);
    var res = vec2<f32>(8.0);

    for(var k = -1; k <= 1; k++) {
        for(var j = -1; j <= 1; j++) {
            for(var i = -1; i <= 1; i++) {
                let g = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash3(n + g);
                let d = g - f + o;
                let d2 = dot(d, d);

                if (d2 < res.x) {
                    res.y = res.x;
                    res.x = d2;
                } else if (d2 < res.y) {
                    res.y = d2;
                }
            }
        }
    }
    return vec2<f32>(sqrt(res.x), sqrt(res.y));
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var w = 0.5;
    var q = p;
    for(var i = 0; i < 4; i++) {
        let v = voronoi(q);
        f += w * v.x;
        q *= 2.0;
        w *= 0.5;
    }
    return f;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * h * k * (1.0 / 6.0);
}

// World -> pendulum frame: mouse orbit, then the pendulum swing about the cremaster anchor.
fn toHang(pos: vec3<f32>, pose: Pose) -> vec3<f32> {
    var q = pos;
    let xz = pose.yaw * q.xz;
    q = vec3<f32>(xz.x, q.y, xz.y);
    q = vec3<f32>(q.x, pose.pitch * q.yz);
    // Idea 2: pendulum sway — rotate about the anchor, so the thread stays taut and the free tip swings most.
    var s = q - vec3<f32>(0.0, ANCHOR_Y, 0.0);
    s = vec3<f32>(pose.swayX * s.xy, s.z);
    s = vec3<f32>(s.x, pose.swayZ * s.yz);
    return s + vec3<f32>(0.0, ANCHOR_Y, 0.0);
}

// Pendulum frame -> body frame (body units): wriggle twist about the long axis + Rotation Speed spin.
fn toBody(q: vec3<f32>, pose: Pose) -> vec3<f32> {
    let p = (q - vec3<f32>(0.0, BODY_Y, 0.0)) / BODY_SCALE;
    // Idea 3: the attached top stays put, the twist grows toward the free (head) end.
    let ang = pose.spin + pose.twist * clamp((5.9 - p.y) / 11.8, 0.0, 1.0);
    let xz = rot(ang) * p.xz;
    return vec3<f32>(xz.x, p.y, xz.y);
}

// Idea 1: seam half-width along the body — widest at the head/thorax end (bottom), closing toward the top.
fn seamWidth(y: f32, gape: f32) -> f32 {
    return gape * (0.35 + 0.65 * (1.0 - smoothstep(-3.0, 2.2, y)));
}

// Dorsal slot (+z side of the body frame), y in [-4.6, 2.2].
fn seamSlot(p: vec3<f32>, gape: f32) -> f32 {
    let w = seamWidth(p.y, gape);
    return max(max(abs(p.x) - w, -p.z), abs(p.y + 1.2) - 3.4);
}

// ----------------------------------------------------------------
// Map Function — returns (step distance in world units, material)
// mat: 1 shell, 2 core, 3 fibres, 4 silk
// ----------------------------------------------------------------
fn map(pos: vec3<f32>, pose: Pose) -> vec2<f32> {
    let t = u.config.x;
    let audio = plasmaBuffer[0].xyz;
    let q = toHang(pos, pose);

    // Idea 2: cremaster silk — cheap analytic SDFs, evaluated outside the voronoi path.
    let tipW = BODY_Y + TIP_Y * BODY_SCALE;
    let ty = clamp(q.y, tipW, ANCHOR_Y + 1.0);
    let dThread = length(vec3<f32>(q.x, q.y - ty, q.z)) - 0.02;
    let dButton = length(q - vec3<f32>(0.0, tipW + 0.1, 0.0)) - 0.055;
    var dSilk = smin(dThread, dButton, 0.08);

    // Body frame before spin/twist (radially symmetric quantities only).
    let pr = (q - vec3<f32>(0.0, BODY_Y, 0.0)) / BODY_SCALE;
    let coreR = 1.0 + sin(t) * 0.1;
    let shellR = coreR + 0.4;
    let rr = length(pr.xz);
    let dShellBase = rr - shellR + pr.y * pr.y * 0.04;

    // Idea 2: silk girdle — the curve where a tilted plane cuts a slightly inflated shell, tubed.
    let gPlane = dot(pr - vec3<f32>(0.0, 2.0, 0.0), normalize(vec3<f32>(0.0, 1.0, 0.32)));
    let dGirdle = length(vec2<f32>(dShellBase - 0.05, gPlane)) - 0.05;
    dSilk = min(dSilk, dGirdle * BODY_SCALE);

    // Conservative bound: every body surface lies inside the shell base (core is >= 0.4 deeper,
    // audio can pull it out by 0.3*bass). Far from the body, skip the five voronoi evaluations.
    let bound = dShellBase - max(audio.x * 0.3 - 0.4, 0.0);
    var dBody = bound;
    var mat = 1.0;
    if (bound < 0.35) {
        let p = toBody(q, pose);

        // Core Capsule
        let dCoreCapsule = length(vec2<f32>(p.x, p.z)) - coreR + p.y * p.y * 0.05; // Tapered

        // Core Displacement
        let coreNoise = fbm(p * 2.0 - vec3<f32>(0.0, t * 1.5, 0.0)) * 0.5;
        let dCore = dCoreCapsule + coreNoise - audio.x * 0.3;

        // Shell
        let complexity = u.zoom_params.x * 5.0 + 3.0;
        let thickness = u.zoom_params.z * 0.3 + 0.1;
        let v = voronoi(p * complexity + vec3<f32>(0.0, t * 0.2, 0.0));
        let cellEdge = v.y - v.x;
        var dShell = max(dShellBase, -(cellEdge - thickness - audio.y * 0.04));

        // Idea 1: eclosion seam — smooth subtraction via smin rounds the split lips.
        dShell = -smin(-dShell, seamSlot(p, pose.gape), 0.12);

        // Fiber Optics (Audio Reactive)
        let dFibers = length(vec2<f32>(p.x, p.z)) - (coreR + audio.x * 1.2) + abs(sin(p.y * (10.0 + audio.z * 4.0) - t * 5.0)) * 0.1;
        let dFib = max(dFibers, dCoreCapsule);

        dBody = min(min(dCore, dShell), dFib);
        if (dBody == dCore) { mat = 2.0; }
        else if (dBody == dFib) { mat = 3.0; }
    }

    let dB = dBody * BODY_SCALE;
    if (dSilk < dB) {
        return vec2<f32>(dSilk * 0.9, 4.0);
    }
    return vec2<f32>(dB * 0.5, mat);
}

// ----------------------------------------------------------------
// Lighting & Shading
// ----------------------------------------------------------------
fn getNormal(p: vec3<f32>, pose: Pose) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, pose).x - map(p - e.xyy, pose).x,
        map(p + e.yxy, pose).x - map(p - e.yxy, pose).x,
        map(p + e.yyx, pose).x - map(p - e.yyx, pose).x
    ));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ----------------------------------------------------------------
// Main Compute
// ----------------------------------------------------------------
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) {
        return;
    }

    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;
    let colorShift = u.zoom_params.w;
    let held = u.zoom_config.w > 0.5;

    var uv = vec2<f32>(id.xy) / res;
    // Screen y=0 is the top; the scene is y-up, so flip pixel y.
    let p = vec2<f32>(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0) * vec2<f32>(res.x / res.y, 1.0);

    // Click fronts (HEAD) + idea 3 wriggle impulses, one pass over the capped ripple list.
    var clickGlow = 0.0;
    var twist = 0.0;
    let uv01 = (vec2<f32>(id.xy) + vec2<f32>(0.5)) / res;
    let aspect = res.x / max(res.y, 1.0);
    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    for (var i = 0u; i < rippleCount; i++) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age > 0.0 && age < 3.0) {
            let delta = vec2<f32>((uv01.x - ripple.x) * aspect, uv01.y - ripple.y);
            clickGlow += exp(-abs(length(delta) - age * 0.2) * 70.0) * exp(-age * 1.4);
            // Idea 3: defensive wriggle — a damped torsional kick; clicks left/right of centre twist opposite ways.
            let dir = select(-1.0, 1.0, ripple.x >= 0.5);
            twist += dir * sin(age * 9.0) * exp(-age * 1.8) * 1.2;
        }
    }

    // Mouse orbit (idle 0.5,0.5 = no orbit): x yaws around the hanging axis, y tilts the view.
    let ms = u.zoom_config.yz * 2.0 - 1.0;
    // Idea 2: gentle two-frequency pendulum sway about the anchor.
    let swayA = 0.06 * sin(time * 0.8) + 0.02 * sin(time * 2.1 + 1.3);
    let swayB = 0.04 * sin(time * 0.63 + 0.5);
    var pose: Pose;
    pose.yaw = rot(ms.x * 3.14);
    pose.pitch = rot(ms.y * 0.45);
    pose.swayX = rot(swayA);
    pose.swayZ = rot(swayB);
    pose.spin = time * u.zoom_params.y * 2.0;
    pose.twist = clamp(twist, -1.6, 1.6);
    // Idea 1: hairline at rest, gapes with bass and with a held pointer.
    pose.gape = 0.05 + audio.x * 0.28 + select(0.0, 0.35, held);
    pose.pad = 0.0;

    let ro = vec3<f32>(0.0, 0.0, 6.0);
    let ta = vec3<f32>(0.0, 0.0, 0.0);

    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = cross(cu, cw);
    let rd = normalize(p.x * cu + p.y * cv + 1.5 * cw);

    let coreCol = vec3<f32>(0.1, 0.6, 1.0) * (1.0 - colorShift) + vec3<f32>(0.8, 0.1, 1.0) * colorShift;
    let fiberCol = vec3<f32>(0.2, 1.0, 0.8);
    let fiberDrive = 0.35 + audio.x + audio.z * 0.8; // non-zero floor at silence

    var t = 0.0;
    var m = -1.0;
    var glow = vec3<f32>(0.0);
    var p_current = ro;

    for (var i = 0; i < 120; i++) {
        p_current = ro + rd * t;
        let d = map(p_current, pose);

        if (abs(d.x) < 0.001 || t > 20.0) {
            m = d.y;
            break;
        }

        t += d.x;

        // Accumulate Glow (distance in HEAD body units so the glow falloff survives the rescale)
        let dg = abs(d.x) / BODY_SCALE;
        if (d.y == 2.0) { // Core
            glow += coreCol * 0.02 / (0.1 + dg) * (0.5 + audio.x * 1.5 + audio.y * 0.4);
        } else if (d.y == 3.0) { // Fibers
            glow += fiberCol * 0.03 / (0.05 + dg) * fiberDrive;
        }
    }

    var col = vec3<f32>(0.02, 0.03, 0.05) * (1.0 - length(p)*0.3); // Background

    if (t < 20.0) {
        let n = getNormal(p_current, pose);
        let l = normalize(vec3<f32>(1.0, 1.0, 1.0));
        let diff = max(dot(n, l), 0.0);
        let rim = 1.0 - max(dot(n, -rd), 0.0);
        let h = normalize(l - rd);

        if (m == 1.0) { // Shell
            col = vec3<f32>(0.05, 0.05, 0.06);

            // Rim light
            col += vec3<f32>(0.1, 0.4, 0.8) * pow(rim, 4.0);

            // Specular
            let spec = pow(max(dot(n, h), 0.0), 32.0);
            col += vec3<f32>(0.5) * spec;

            // Idea 1: core light spilling over the seam lips, scaled by how far the split gapes.
            let pb = toBody(toHang(p_current, pose), pose);
            let lip = abs(pb.x) - seamWidth(pb.y, pose.gape);
            let along = 1.0 - smoothstep(3.0, 3.6, abs(pb.y + 1.2));
            let spill = exp(-max(lip, 0.0) * 14.0) * smoothstep(-0.1, 0.3, pb.z) * along;
            col += coreCol * spill * (0.25 + pose.gape * 4.0) * (0.6 + audio.x * 0.8);
        } else if (m == 2.0) { // Core (should be occluded by shell, but just in case)
            col = vec3<f32>(1.0) * diff;
        } else if (m == 3.0) { // Fibres: lit teal strands with an emissive floor
            col = mix(fiberCol, coreCol, 0.35) * (0.15 + 0.55 * diff) + fiberCol * 0.2 * fiberDrive;
        } else if (m == 4.0) { // Silk thread / girdle / cremaster pad
            let sheen = pow(max(dot(n, h), 0.0), 24.0);
            col = vec3<f32>(0.78, 0.76, 0.7) * (0.1 + 0.5 * diff) + vec3<f32>(0.1, 0.3, 0.5) * pow(rim, 3.0) + vec3<f32>(0.4) * sheen;
        }
    }

    col += glow;

    // Click fronts make the chrysalis flare without changing its raymarched silhouette.
    col += mix(vec3<f32>(0.15, 0.8, 1.2), vec3<f32>(1.0, 0.2, 1.1), colorShift) * clickGlow * (0.25 + audio.z * 0.65);

    // Add some noise/dust
    col += hash3(vec3<f32>(p_current.xy * 100.0, time)).x * 0.03;

    let coord = vec2<i32>(id.xy);
    let history = textureLoad(dataTextureC, coord, 0);
    let hdrColor = clamp(mix(col, history.rgb, 0.06 + audio.x * 0.08), vec3<f32>(0.0), vec3<f32>(7.0));
    let mappedColor = acesToneMap(hdrColor);
    let hit = t < 20.0;
    let alpha = clamp(select(0.03, 0.32 + length(mappedColor) * 0.32, hit) + clickGlow * 0.12, 0.02, 0.98);
    let depth = select(0.0, clamp(1.0 - t / 20.0, 0.0, 1.0), hit);

    textureStore(writeTexture, coord, vec4<f32>(mappedColor, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
