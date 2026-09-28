// ═══════════════════════════════════════════════════════════════════
//  Gen Bismuth Crystal Citadel - Physical Light Transmission
//  Category: generative
//  Features: raymarch, audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: molten melt-pool bands in the tier gaps that underlight the tiers; axial beacon column mirrored in every face via Schlick metal Fresnel
//  A packing: HDR linear RGB (pre-ACES) + semantic alpha; C read back as HDR for a light rising trail
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

const IOR_BISMUTH: f32 = 1.8;
const TIER_SPACING: f32 = 4.0;
const POOL_RADIUS: f32 = 2.9;
const POOL_HALF: f32 = 0.04;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

fn hash31(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Cell-local height inside the 4-unit tier repeat (tiers span |y| < 1.5, gaps at |y| > 1.5).
fn tierLocalY(y: f32) -> f32 {
    return fract(y / TIER_SPACING + 0.5) * TIER_SPACING - TIER_SPACING * 0.5;
}

// Hollow bismuth box of one segment (HEAD d1 / inner_hollow, verbatim dimensions).
fn wallSd(p: vec3<f32>) -> f32 {
    let basePos = vec3<f32>(2.0, 0.0, 0.0);
    let d1 = sdBox(p - basePos, vec3<f32>(1.0, 1.5, 1.0));
    let innerSize = vec3<f32>(0.8, 1.6, 0.8);
    let inner_hollow = sdBox(p - basePos, innerSize);
    return max(d1, -inner_hollow);
}

// FIX: HEAD tiled terrace cubes through ALL space (map < 0 everywhere -> blank frame).
// Terrace cubes (same pStep grid, same 0.45*stepSize half-size) now only grow on cells whose
// centre lies against the wall; the 2x2x2 nearest cells are checked so the bound stays valid.
fn terraceSd(p: vec3<f32>, stepSize: f32, dw: f32) -> f32 {
    if (dw > 1.3 * stepSize) {
        return dw - 1.2 * stepSize;
    }
    let g = p / stepSize;
    let cell = floor(g);
    let q = g - cell - vec3<f32>(0.5);
    let o = select(vec3<f32>(-1.0), vec3<f32>(1.0), q >= vec3<f32>(0.0));
    var best = 0.52 * stepSize;
    for (var i = 0u; i < 8u; i++) {
        let off = vec3<f32>(f32(i & 1u), f32((i >> 1u) & 1u), f32((i >> 2u) & 1u)) * o;
        let pStep = (cell + off + vec3<f32>(0.5)) * stepSize;
        let h = hash31(pStep * 7.13 + vec3<f32>(3.1, 5.7, 1.3));
        if (wallSd(pStep) < stepSize * (0.1 + 0.25 * h)) {
            let terraceSize = stepSize * 0.45;
            best = min(best, sdBox(p - pStep, vec3<f32>(terraceSize)) - 0.03 * stepSize);
        }
    }
    return best;
}

// Idea 1: molten melt-pool band — a rippling disc of bismuth melt in every tier gap (|y| = 2).
fn poolSd(ly: f32, radius: f32, time: f32, mids: f32) -> f32 {
    let ripple = sin(radius * 9.0 - time * 2.5) * 0.012 * (1.0 + mids * 0.6);
    let slab = (TIER_SPACING * 0.5 - abs(ly)) - POOL_HALF - ripple;
    return max(slab, radius - POOL_RADIUS);
}

// Idea 1: melt colour (hot ember core, silvery ripple crests).
fn meltColor(radius: f32, time: f32, bass: f32) -> vec3<f32> {
    let heat = mix(0.55, 1.0, 1.0 - clamp(radius / POOL_RADIUS, 0.0, 1.0));
    let crest = sin(radius * 9.0 - time * 2.5) * 0.5 + 0.5;
    let ember = vec3<f32>(1.0, 0.42, 0.12) * 1.8 * heat;
    let sheen = vec3<f32>(1.3, 1.22, 1.1);
    return mix(ember, sheen, 0.22 * crest) * (1.0 + bass * 0.8);
}

// Idea 2: closest approach of a ray segment to the tower axis (x = z = 0).
fn axisApproach(o: vec3<f32>, d: vec3<f32>, sMax: f32) -> vec2<f32> {
    let a = dot(d.xz, d.xz);
    let s = clamp(-dot(o.xz, d.xz) / max(a, 1e-5), 0.0, sMax);
    return vec2<f32>(length(o.xz + d.xz * s), s);
}

// Idea 2: beacon column emission seen along a ray (rising light bands on the axis).
fn beaconGlow(o: vec3<f32>, d: vec3<f32>, sMax: f32, width: f32, time: f32) -> vec3<f32> {
    let ap = axisApproach(o, d, sMax);
    let yb = o.y + d.y * ap.y;
    let pulse = 0.7 + 0.3 * sin(yb * 1.3 - time * 2.0);
    let core = width / (ap.x * ap.x + width);
    return vec3<f32>(0.75, 0.85, 1.0) * pulse * core * exp(-ap.y * 0.03);
}

// Idea 1 + 2: melt pool seen by a (reflected) ray at the next gap plane along it.
fn poolSeen(o: vec3<f32>, d: vec3<f32>, time: f32, bass: f32) -> vec3<f32> {
    if (abs(d.y) < 1e-3) {
        return vec3<f32>(0.0);
    }
    let ly = tierLocalY(o.y);
    let dy = select(ly + TIER_SPACING * 0.5, TIER_SPACING * 0.5 - ly, d.y > 0.0);
    let s = dy / abs(d.y);
    let hp = o + d * s;
    let rr = length(hp.xz);
    let inside = 1.0 - smoothstep(POOL_RADIUS - 0.2, POOL_RADIUS, rr);
    return meltColor(rr, time, bass) * inside * exp(-s * 0.08);
}

fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;
    let mids = plasmaBuffer[0].y;

    let twist = p.y * 0.05;
    let p_xz = rot(twist) * p.xz;
    p.x = p_xz.x;
    p.z = p_xz.y;

    let spacingY = TIER_SPACING;
    p.y = fract(p.y / spacingY + 0.5) * spacingY - spacingY * 0.5;

    let angle = atan2(p.z, p.x);
    let radius = length(p.xz);
    let segments = 6.0;
    let segmentAngle = 6.28318 / segments;
    let a = angle + 3.14159;
    let a_mod = fract(a / segmentAngle) * segmentAngle - segmentAngle * 0.5;

    p.x = radius * cos(a_mod);
    p.z = radius * sin(a_mod);

    let stepSize = u.zoom_params.x * 0.5 + 0.1;

    let dw = wallSd(p);
    let d2 = terraceSd(p, stepSize, dw);

    var d = min(dw, d2);

    let crystalPos = vec3<f32>(
        1.5 + sin(u.config.x * 0.5 + p.y) * 0.2,
        0.0,
        0.0
    );
    let d3 = sdBox(p - crystalPos, vec3<f32>(0.3, 0.8, 0.3));
    d = smin(d, d3, 0.2);

    // Idea 1: melt pool in the tier gap.
    let dp = poolSd(p.y, radius, u.config.x, mids);
    if (dp < d) {
        return vec2<f32>(dp, 2.0);
    }
    return vec2<f32>(d, 1.0);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let g = vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    );
    return g / max(length(g), 1e-6);
}

// FIX: HEAD AO was the constant 1 - 100/100 -> 0.5; real few-tap occlusion along the normal.
fn calcAO(p: vec3<f32>, n: vec3<f32>) -> f32 {
    var occ = 0.0;
    var sca = 1.0;
    for (var i = 0; i < 5; i++) {
        let h = 0.02 + 0.1 * f32(i);
        let dd = map(p + n * h).x;
        occ += (h - dd) * sca;
        sca *= 0.85;
    }
    return clamp(1.0 - 1.6 * occ, 0.0, 1.0);
}

// Fresnel for metals
fn fresnelMetal(cosTheta: f32, F0: vec3<f32>) -> vec3<f32> {
    return F0 + (vec3<f32>(1.0) - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);

    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) {
        return;
    }
    let coord = vec2<i32>(id.xy);

    let uv = (fragCoord * 2.0 - dims) / dims.y * vec2<f32>(1.0, -1.0);

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let clock = u.config.x;

    // Parameters
    let stepSize = u.zoom_params.x * 0.5 + 0.1;
    let metallic = u.zoom_params.z * (1.0 + bass * 0.4);
    let iridescence = u.zoom_params.w * (1.0 + treble * 0.3);
    let oxidePurity = 0.7 + u.zoom_params.x * 0.3;

    // FIX: ascension phase no longer multiplies the absolute clock by (1 + mids) (camera jumps).
    let time = clock * u.zoom_params.y;

    // FIX: mouse was dead (0..1 mouse divided by pixels, rotated rd overwritten).
    // Pointer x orbits the tower, pointer y tilts the gaze; centre = HEAD camera path.
    let mouse = u.zoom_config.yz;
    let orbit = (mouse.x - 0.5) * 6.28318;
    let tilt = (0.5 - mouse.y) * 6.0;
    let ro = vec3<f32>(sin(orbit) * 5.0, time * 2.0, -cos(orbit) * 5.0);

    let ta = vec3<f32>(0.0, time * 2.0 + 2.0 + tilt, 0.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);

    // Raymarching
    var t = 0.0;
    var d = 0.0;
    var m = -1.0;
    let maxSteps = 140;
    let maxDist = 50.0;
    var hit = false;

    for (var i = 0; i < maxSteps; i++) {
        let p = ro + rd * t;
        let res = map(p);
        d = res.x;
        m = res.y;
        if (d < 0.001) { hit = true; break; }
        if (t > maxDist) { break; }
        t += d * 0.8;
    }
    // Out of steps while grazing a surface still counts as a hit (avoids pinholes).
    if (!hit && t < maxDist && d < 0.02) { hit = true; }

    // Background
    var col = vec3<f32>(0.02, 0.02, 0.03);
    col += vec3<f32>(0.05, 0.08, 0.12) * max(0.0, rd.y);

    var alpha = 0.9; // Background is semi-transparent for layering
    let tEnd = select(maxDist, t, hit);

    if (hit) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let v = -rd;
        let ndotv = clamp(dot(n, v), 0.0, 1.0);
        let fresnel = pow(clamp(1.0 - ndotv, 0.0, 1.0), 5.0);
        let radius = length(p.xz);
        let ly = tierLocalY(p.y);
        let refl = reflect(rd, n);

        // Idea 2: bismuth mirror F0 (metal) never falls below the oxide's dielectric F0 from IOR_BISMUTH.
        let f0Oxide = pow((IOR_BISMUTH - 1.0) / (IOR_BISMUTH + 1.0), 2.0);
        let F0_bismuth = vec3<f32>(0.75, 0.8, 0.85);
        let metalFresnel = fresnelMetal(ndotv, max(F0_bismuth * metallic, vec3<f32>(f0Oxide)));

        if (m > 1.5) {
            // Idea 1: melt-pool surface — emissive melt that mirrors the beacon column.
            let melt = meltColor(radius, clock, bass);
            let beaconInMelt = beaconGlow(p + n * 0.01, refl, 30.0, 0.02, clock);
            col = melt + beaconInMelt * 0.6 + vec3<f32>(0.9, 0.9, 1.0) * fresnel * 0.4;
            alpha = 1.0;
        } else {
            // Mouse-controlled secondary light: a lamp offset from the camera toward the pointer.
            let mouseLightPos = ro + uu * (mouse.x - 0.5) * 8.0 + vv * (0.5 - mouse.y) * 6.0 + ww * 2.0;

            let lig = normalize(vec3<f32>(1.0, 2.0, -1.0));
            let l_mouse = normalize(mouseLightPos - p);

            let dif = max(dot(n, lig), 0.0);
            let dif_mouse = max(dot(n, l_mouse), 0.0);

            let hal = normalize(lig - rd);
            let spec = pow(max(dot(n, hal), 0.0), 32.0);

            // Thin-film interference
            let interferenceOffset = p.y * 0.1 + p.x * 0.05 + clock * 0.1;
            let iriPhase = fresnel * iridescence + interferenceOffset;

            // Bismuth color palette
            let c_a = vec3<f32>(0.5, 0.5, 0.5);
            let c_b = vec3<f32>(0.5, 0.5, 0.5);
            let c_c = vec3<f32>(1.0, 1.0, 0.8);
            let c_d = vec3<f32>(0.0, 0.33, 0.67);

            let iridColor = palette(iriPhase, c_a, c_b, c_c, c_d);

            // Base bismuth material
            let baseColor = vec3<f32>(0.08, 0.08, 0.1);

            // Combine lighting
            var litColor = baseColor * (dif * 0.7 + dif_mouse * 0.5 + 0.2);
            litColor += iridColor * fresnel * 0.8 * oxidePurity;
            litColor += vec3<f32>(1.0) * spec * metallic;

            // Terrace pattern edge highlights
            let terracePattern = sin(p.x * 10.0) * sin(p.y * 10.0) * sin(p.z * 10.0);
            litColor += vec3<f32>(0.3, 0.5, 0.6) * max(0.0, terracePattern) * fresnel * 0.5;

            // Idea 1: melt underlight — the pool below lights down-facing faces (tier undersides),
            // the pool above lights up-facing ledges; iridescent tint picks up the melt glow.
            let poolMask = 1.0 - smoothstep(POOL_RADIUS - 0.3, POOL_RADIUS + 0.9, radius);
            let dBelow = max(ly + TIER_SPACING * 0.5 - POOL_HALF, 0.0);
            let dAbove = max(TIER_SPACING * 0.5 - ly - POOL_HALF, 0.0);
            let under = max(-n.y, 0.0) * exp(-dBelow * 1.8) + max(n.y, 0.0) * exp(-dAbove * 1.8)
                      + 0.25 * (exp(-dBelow * 2.5) + exp(-dAbove * 2.5));
            let meltLight = meltColor(min(radius, POOL_RADIUS), clock, bass) * under * poolMask;
            litColor += meltLight * mix(vec3<f32>(0.6), iridColor, 0.35) * 0.7;

            // Idea 2: axial beacon — diffuse light from the column, and every metal face mirrors
            // the column and the nearest melt pool along reflect(rd, n), weighted by metalFresnel.
            let toAxis = normalize(vec3<f32>(-p.x, 0.0, -p.z) + vec3<f32>(1e-4, 0.0, 0.0));
            let beaconDif = max(dot(n, toAxis), 0.0) / (1.0 + radius * radius * 0.25);
            litColor += vec3<f32>(0.75, 0.85, 1.0) * beaconDif * 0.35;
            let skyRefl = vec3<f32>(0.02, 0.02, 0.03) + vec3<f32>(0.05, 0.08, 0.12) * max(0.0, refl.y);
            let mirrored = beaconGlow(p + n * 0.01, refl, 30.0, 0.02, clock) * 1.4
                         + poolSeen(p + n * 0.01, refl, clock, bass) * 0.5
                         + skyRefl;
            litColor += mirrored * metalFresnel;

            col = litColor;

            // Metallic transmission alpha (FIX: HEAD could exceed 1 for Metallic Shine > ~1).
            alpha = clamp(mix(0.3, 1.0, metallic * 0.7 + fresnel * 0.3), 0.0, 1.0);
        }

        // Ambient occlusion
        let ao = calcAO(p, n);
        col *= mix(0.5, 1.0, ao);

        // Distance fog
        col = mix(col, vec3<f32>(0.02, 0.02, 0.03), 1.0 - exp(-0.015 * t));
    }

    // Idea 2: the beacon column itself, seen through the gaps up to the first hit.
    let beam = beaconGlow(ro, rd, tEnd, 0.004, clock);
    col += beam * 0.9;
    alpha = clamp(alpha + dot(beam, vec3<f32>(0.1)), 0.0, 1.0);

    // Light rising trail from exact C history (A stores HDR, so no double tone-map).
    let prev = textureLoad(dataTextureC, coord, 0);
    let hdr = mix(col, max(prev.rgb, vec3<f32>(0.0)), 0.15);
    textureStore(dataTextureA, coord, vec4<f32>(hdr, alpha));

    // Vignette + ACES on display only
    let vig = 1.0 - 0.3 * length(uv);
    let display = acesToneMap(max(hdr * vig * 1.4, vec3<f32>(0.0)));

    textureStore(writeTexture, coord, vec4<f32>(display, alpha));
    let depth = select(0.0, clamp(1.0 - t / maxDist, 0.0, 1.0), hit);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
