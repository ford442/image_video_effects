// ═══════════════════════════════════════════════════════════════════
//  Mushroom Mandala Garden
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: lamellulae gill tiers (short secondary/tertiary gills inserted toward the cap margin); Buller's-drop ballistospore discharge (catapult flash, drag-stopped sporabola hook, gravity sedimentation)
//  A packing: ACES display RGBA in A
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Cap Count, .y = Breathe Rate, .z = Gill Detail, .w = Bioluminescence
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530718;

fn palette(t: f32) -> vec3<f32> {
    return vec3<f32>(0.54, 0.48, 0.52) + vec3<f32>(0.46, 0.51, 0.48) *
        cos(TAU * (vec3<f32>(1.0, 0.69, 0.43) * t + vec3<f32>(0.03, 0.31, 0.62)));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

// ── IDEA 2 helper: Buller's-drop ballistospore discharge ──
// A basidiospore is fired off its sterigma by the fusion of Buller's drop:
// a violent sideways launch that air drag kills within a fraction of a
// millimetre (the "sporabola" hook), after which the spore sediments straight
// down at terminal velocity between the gills. Spores live on a lattice of
// discharge sites; each pixel checks the sites above it that could have
// dropped a spore through it.
fn ballistospores(p: vec2<f32>, time: f32, rate: f32, treble: f32) -> vec2<f32> {
    let cs = 0.045;
    var glow = 0.0;
    var flash = 0.0;
    let base = floor(p / cs);
    for (var dx = -1; dx <= 1; dx = dx + 1) {
        for (var k = 0; k < 4; k = k + 1) {
            let cellId = base - vec2<f32>(f32(dx), f32(k));
            let h = hash21(cellId + 17.3);
            // only a fraction of sites are ripe; treble ripens more of them
            if (h < 0.55 - treble * 0.3) { continue; }
            let h2 = hash21(cellId * 1.37 + 4.1);
            let ph = fract(time * rate * (0.6 + h2 * 0.8) + h * 7.0);
            let launch = (cellId + vec2<f32>(0.25 + 0.5 * h2, 0.35)) * cs;
            let side = select(-1.0, 1.0, h2 > 0.5);
            let hook = side * cs * 0.45 * (1.0 - exp(-ph * 28.0));
            let fall = ph * cs * 3.6;
            let d = p - (launch + vec2<f32>(hook, fall));
            let r = cs * (0.07 + 0.03 * h);
            glow += exp(-dot(d, d) / (r * r)) * (1.0 - ph * 0.7);
            let fd = p - launch;
            flash += exp(-dot(fd, fd) / (r * r * 4.0)) * exp(-ph * 60.0);
        }
    }
    return vec2<f32>(glow, flash);
}

fn historyLoadUV(uv: vec2<f32>) -> vec4<f32> {
    let size = vec2<i32>(textureDimensions(dataTextureC));
    let pixel = vec2<i32>(floor(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * vec2<f32>(size)));
    return textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), size - vec2<i32>(1)), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let time = u.config.x;
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    let capCount = u.zoom_params.x;
    let breatheRate = u.zoom_params.y;
    let gillDetail = u.zoom_params.z;
    let bioluminescence = u.zoom_params.w;
    let aspect = resolution.x / resolution.y;
    var p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseP = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseDelta = p - mouseP;
    let mouseDistance = max(length(mouseDelta), 0.001);
    let dragMask = exp(-mouseDistance * (5.0 + capCount * 3.0)) * u.zoom_config.w;
    p += mouseDelta / mouseDistance * dragMask * sin(time * 3.0) * (0.03 + gillDetail * 0.08);

    let radius = max(length(p), 0.002);
    let angle = atan2(p.y, p.x);
    let segments = 5.0 + floor(capCount * 9.0);
    let petalAngle = abs(fract(angle / TAU * segments + 0.5) - 0.5) * 2.0;
    let breathe = 1.0 + sin(time * (0.8 + breatheRate * 4.5) + radius * 12.0) * (0.05 + bass * 0.06);
    let ringCoord = fract(radius * (4.0 + capCount * 7.0) * breathe) - 0.5;
    let cap = exp(-pow(ringCoord / (0.18 + capCount * 0.06), 2.0)) * smoothstep(0.95, 0.10, petalAngle);
    let stem = exp(-petalAngle * (10.0 + capCount * 15.0)) * smoothstep(0.48, 0.05, abs(ringCoord));
    // ── IDEA 1: lamellulae gill tiers ──
    // Full-length lamellae run from stem to margin; as the cap widens, short
    // lamellulae are inserted between them (secondary at half spacing in the
    // outer half, tertiary at quarter spacing near the margin). ringCoord > 0
    // is the outward/margin side of each cap band. Gill Detail sets the tiers.
    let gillPhase = petalAngle * (18.0 + gillDetail * 52.0) - time * (1.0 + breatheRate * 2.0);
    let lamella = pow(0.5 + 0.5 * cos(gillPhase), 9.0);
    let lamellulaII = pow(0.5 + 0.5 * cos(gillPhase + 3.14159265), 11.0) * smoothstep(-0.04, 0.10, ringCoord);
    let lamellulaIII = pow(0.5 + 0.5 * cos(2.0 * gillPhase + 3.14159265), 14.0) * smoothstep(0.08, 0.22, ringCoord) * gillDetail;
    let gills = clamp(lamella + lamellulaII * 0.75 + lamellulaIII * 0.55, 0.0, 1.4) * cap;
    let sporeRate = 0.25 + breatheRate * 0.7;
    let buller = ballistospores(p, time, sporeRate, treble);
    let sporeLane = fract(radius * (8.0 + gillDetail * 16.0) - time * (0.7 + breatheRate * 2.5));
    let spores = exp(-pow((sporeLane - 0.5) / 0.08, 2.0)) * pow(hash21(floor(p * 40.0 + 70.0)), 5.0);
    let myceliumPhase = sin(p.x * (24.0 + gillDetail * 26.0) + sin(p.y * 13.0 - time * breatheRate * 2.0) * 3.0);
    let mycelium = pow(1.0 - abs(myceliumPhase), 14.0) * smoothstep(0.72, 0.08, radius);
    let fairyRing = exp(-abs(fract(radius * (7.0 + capCount * 9.0) - time * 0.18) - 0.5) * 24.0) * (0.5 + 0.5 * cos(angle * segments));

    var clickSpores = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 3.4) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let distanceToClick = length(delta);
            let front = abs(distanceToClick - age * (0.14 + breatheRate * 0.16));
            let rays = pow(0.5 + 0.5 * cos(atan2(delta.y, delta.x) * 13.0 + age * 5.0), 8.0);
            clickSpores += (1.0 - smoothstep(0.0, 0.035, front)) * (0.35 + rays) * (1.0 - age / 3.4);
        }
    }

    let hue = angle / TAU + radius * 0.55 + time * 0.08 + bioluminescence * 0.35;
    var hdr = palette(hue) * cap * (0.9 + bioluminescence * 2.1 + mids * 0.5);
    hdr += palette(hue + 0.28) * (gills * 1.8 + stem * 0.8) * (0.6 + treble * 0.5);
    hdr += palette(hue + 0.6) * (spores * 1.2 + clickSpores * 1.8);
    hdr += palette(hue + 0.72) * buller.x * (0.5 + bioluminescence * 0.9) * (1.0 + treble * 0.4);
    hdr += vec3<f32>(1.0, 0.95, 0.85) * buller.y * (1.2 + bass * 0.5);
    hdr += palette(hue + 0.46) * (mycelium * 0.75 + fairyRing * 0.55) * (0.5 + mids * 0.5);
    hdr += vec3<f32>(0.4, 1.0, 0.65) * dragMask * (0.5 + bioluminescence);
    let historyUV = clamp(uv + vec2<f32>(sin(angle) / max(aspect, 0.001), -cos(angle)) * (0.002 + breatheRate * 0.006), vec2<f32>(0.0), vec2<f32>(1.0));
    let history = historyLoadUV(historyUV);
    hdr = mix(hdr, history.rgb, clamp(0.10 + bioluminescence * 0.16 + dragMask * 0.14, 0.0, 0.40));
    let structure = clamp(cap + gills * 0.5 + spores + mycelium * 0.3 + clickSpores * 0.45 + buller.x * 0.4 + buller.y * 0.3, 0.0, 1.0);
    let output = vec4<f32>(acesToneMap(hdr * (1.0 + bass * 0.15)), clamp(0.12 + structure * 0.86, 0.0, 1.0));
    textureStore(writeTexture, coord, output);
    textureStore(dataTextureA, coord, output);
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(0.10 + cap * 0.48 + gills * 0.22 + clickSpores * 0.18, 0.0, 0.95), 0.0, 0.0, 0.0));
}
