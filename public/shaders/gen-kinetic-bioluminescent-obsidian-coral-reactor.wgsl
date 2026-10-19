// ═══════════════════════════════════════════════════════════════════
//  Kinetic Bioluminescent Obsidian-Coral Reactor
//  Category: generative
//  Features: audio-reactive, mouse-control, volumetric, raymarching,
//            aces-tone-map, semantic-alpha, depth-aware
//  Complexity: High
//  Upgraded: 2026-10-18
//  Ideas: fBm ridge-vein filaments; coral/obsidian contact meniscus; smoking-mirror obsidian (Fresnel reflection march picks up the coral glow); Menger carve-generation gloss (hull weathered, finer holes mirror-polished)
//  A packing: ACES display RGBA (rgb = tone-mapped display history; a = ray coverage)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// Math and constants
const PI: f32 = 3.14159265359;
const MAX_STEPS: i32 = 96;
// fbm x3 coral raises the field's Lipschitz bound; march with relaxed steps.
const STEP_SCALE: f32 = 0.7;
const SURF_DIST: f32 = 0.005;
const MAX_DIST: f32 = 50.0;
// The legacy controls exposed six values, but the canonical ABI carries four.
// Keep unavailable Glow / Void at their saved defaults.
const GLOW_INTENSITY: f32 = 2.0;
const VOID_DARKNESS: f32 = 0.8;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Polynomial smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 3D hash
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(q) * 43758.5453123);
}

// 3D noise (value noise)
fn noise3D(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    return mix(
        mix(mix(dot(hash3(i + vec3<f32>(0.,0.,0.)), f - vec3<f32>(0.,0.,0.)),
                dot(hash3(i + vec3<f32>(1.,0.,0.)), f - vec3<f32>(1.,0.,0.)), u.x),
            mix(dot(hash3(i + vec3<f32>(0.,1.,0.)), f - vec3<f32>(0.,1.,0.)),
                dot(hash3(i + vec3<f32>(1.,1.,0.)), f - vec3<f32>(1.,1.,0.)), u.x), u.y),
        mix(mix(dot(hash3(i + vec3<f32>(0.,0.,1.)), f - vec3<f32>(0.,0.,1.)),
                dot(hash3(i + vec3<f32>(1.,0.,1.)), f - vec3<f32>(1.,0.,1.)), u.x),
            mix(dot(hash3(i + vec3<f32>(0.,1.,1.)), f - vec3<f32>(0.,1.,1.)),
                dot(hash3(i + vec3<f32>(1.,1.,1.)), f - vec3<f32>(1.,1.,1.)), u.x), u.y), u.z);
}

// FBM
fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var q = p;
    for (var i = 0; i < 4; i++) {
        f += amp * noise3D(q);
        q *= 2.0;
        amp *= 0.5;
    }
    return f;
}

// Box SDF
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// Distance to Obsidian Lattice and Coral.
// y = material: coral 1.0; obsidian 0.1 * carve generation (0 = tunnel hull,
// 1..3 = the Menger hole level whose face this is).
// z carries the distance between the two fields for contact-line shading.
fn map(p: vec3<f32>, mouse_pos: vec3<f32>, audio_bass: f32) -> vec3<f32> {
    var d_obj = 0.0; // Material ID

    // Domain repetition for brutalist tunnel
    let c = vec3<f32>(8.0);
    var q = p;
    q.x = (fract(q.x / c.x + 0.5) - 0.5) * c.x;
    q.y = (fract(q.y / c.y + 0.5) - 0.5) * c.y;
    // HEAD repeated only x/y, so the lattice was a single |z| < 3 slab: the camera
    // (z = time * fluid_speed) left it after ~5 s and every later frame was black void.
    q.z = (fract(q.z / c.z + 0.5) - 0.5) * c.z;

    // Base geometry: Menger-like structure
    var d_obsidian = sdBox(q, vec3<f32>(3.0));

    // Subtractions for lattice holes, using Lattice Complexity parameter
    let complexity = max(1.0, u.zoom_params.w);
    var carve_gen = 0.0;
    for (var i = 0.0; i < 5.0; i += 1.0) {
        if (i >= complexity) { break; }
        let s = pow(3.0, i);
        var sub_q = (fract(p * s) - 0.5) / s;
        let sub_box = sdBox(sub_q, vec3<f32>(0.35 / s));
        if (-sub_box > d_obsidian) { carve_gen = min(i + 1.0, 3.0); }
        d_obsidian = max(d_obsidian, -sub_box);
    }

    // Hollow out a central tunnel
    // Infinite along z (HEAD capped it at |z| < MAX_DIST).
    let tq = abs(p.xy) - vec2<f32>(2.0);
    let tunnel = -(length(max(tq, vec2<f32>(0.0))) + min(max(tq.x, tq.y), 0.0));
    if (tunnel > d_obsidian) { carve_gen = 0.0; }
    d_obsidian = max(d_obsidian, tunnel);

    // Coral Growth SDF
    let coral_density = u.zoom_params.y;
    let fluid_speed = u.zoom_params.z;
    // fbm is zero-centred with ~±0.19 range: unscaled, coral only won ~15% of the
    // lattice and the reactor read as a bare grey tunnel. ×3 lets it overgrow the ribs.
    let noise_val = fbm(p * 0.5 + vec3<f32>(0.0, 0.0, -u.config.x * fluid_speed)) * 3.0;

    // Audio pushes the coral outward
    let audio_push = audio_bass * 0.5;

    // Coral grows along the obsidian, slightly offset
    let d_coral = d_obsidian + 0.2 - noise_val * coral_density - audio_push;

    // Combine them with smooth min for blending
    let d = smin(d_obsidian, d_coral, 0.8);

    // Mouse influence (perturbs surface when close)
    let mouse_dist = length(p - mouse_pos);
    let mouse_influence = smoothstep(3.0, 0.0, mouse_dist);
    let final_d = d - mouse_influence * 0.1;

    // Material logic
    if (d_coral < d_obsidian + 0.1) {
        d_obj = 1.0; // Coral
    } else {
        d_obj = carve_gen * 0.1; // Obsidian, tagged by carve generation
    }

    return vec3<f32>(final_d, d_obj, abs(d_coral - d_obsidian));
}

// Calculate normal
fn calcNormal(p: vec3<f32>, mouse_pos: vec3<f32>, audio_bass: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, mouse_pos, audio_bass).x - map(p - e.xyy, mouse_pos, audio_bass).x,
        map(p + e.yxy, mouse_pos, audio_bass).x - map(p - e.yxy, mouse_pos, audio_bass).x,
        map(p + e.yyx, mouse_pos, audio_bass).x - map(p - e.yyx, mouse_pos, audio_bass).x
    ));
}

// Cosine palette
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(2.0 * PI * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coords = vec2<i32>(global_id.xy);
    if (coords.x >= i32(dims.x) || coords.y >= i32(dims.y)) { return; }

    let base_uv = vec2<f32>(coords) / vec2<f32>(dims);
    var uv = base_uv * 2.0 - 1.0;
    let aspect = f32(dims.x) / f32(dims.y);
    uv.x *= aspect;

    let time = u.config.x;

    // Audio Reactivity
    let bass = plasmaBuffer[0].x;
    let treble = plasmaBuffer[0].z;
    let fluid_speed = u.zoom_params.z;

    // Mouse Interaction
    var mouse_pos = vec3<f32>(0.0, 0.0, -100.0); // Default far away
    if (u.zoom_config.w > 0.5) { // Mouse down
        let muv = u.zoom_config.yz * 2.0 - 1.0;
        // The camera basis maps screen +x to world -x and screen-down to world +y
        // (HEAD placed the lantern point-mirrored from the cursor).
        mouse_pos = vec3<f32>(-muv.x * 5.0, muv.y * 5.0, 2.0 + time * fluid_speed);
    }

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -2.0 + time * fluid_speed); // Camera moves forward
    // Mild sway based on time
    ro.x += sin(time * 0.5) * 0.5;
    ro.y += cos(time * 0.4) * 0.5;

    // Look-at setup
    let lookAtTarget = vec3<f32>(0.0, 0.0, ro.z + 5.0);
    let ww = normalize(lookAtTarget - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));

    // Mild chromatic aberration for ray directions
    let shift = 0.01;
    var final_color = vec3<f32>(0.0);
    var center_depth = 0.0;
    var center_coverage = 0.0;
    var center_emission = 0.0;
    var mirror_rgb = vec3<f32>(0.0);

    // Trace 3 rays for RGB split (chromatic aberration on periphery)
    let lens_dist = length(uv);
    let r_shift = lens_dist * shift;

    let offsets = array<f32, 3>(-r_shift, 0.0, r_shift);

    for (var c = 0; c < 3; c++) {
        var rd = normalize(uv.x * uu + uv.y * vv + (1.5 + offsets[c]) * ww);

        var t = 0.0;
        var p = ro;
        var mat_id = 0.0;
        var dist_to_coral = 0.0;
        var contact_gap = 1.0;
        var hit = false;

        // Raymarch
        for (var i = 0; i < MAX_STEPS; i++) {
            p = ro + rd * t;
            let res = map(p, mouse_pos, bass);
            let d = res.x;

            if (res.y > 0.5) {
                // Keep track of how close we get to the coral for subsurface glow
                dist_to_coral += exp(-d * 2.0);
            }

            if (abs(d) < SURF_DIST) { hit = true; }
            if (hit || t > MAX_DIST) {
                mat_id = res.y;
                contact_gap = res.z;
                break;
            }
            t += d * STEP_SCALE;
        }

        var col = vec3<f32>(0.0);
        var ray_emission = 0.0;

        // Step-exhausted rays are void, not obsidian.
        if (!hit) { t = MAX_DIST; }
        if (hit) {
            let n = calcNormal(p, mouse_pos, bass);

            // Mouse Light (Lantern effect)
            var light_pos = ro + vec3<f32>(0.0, 0.0, 2.0); // Default headlight
            if (u.zoom_config.w > 0.5) {
                light_pos = mouse_pos;
            }

            let l = normalize(light_pos - p);
            let dif = max(dot(n, l), 0.0);
            let view_dir = normalize(ro - p);
            var refl = reflect(-l, n); // Switched from reserved keyword ref

            // Idea 4 — carve-generation gloss: the hull face left by the tunnel cut
            // is weathered (broad, dim lobe); each finer Menger hole generation is a
            // fresher fracture face, polished toward a mirror.
            let carve_gen = round(mat_id * 10.0);
            let polish = select(0.0, clamp(carve_gen / 3.0, 0.0, 1.0) * 0.6 + 0.4, carve_gen > 0.5);
            var mirror_n = n;

            // Treble causes local micro-fractures in obsidian normal
            if (mat_id < 0.5) { // Obsidian
                let fracture = fbm(p * 20.0) * treble * 0.1;
                refl = reflect(-normalize(l + fracture), normalize(n + fracture));
                // Weathered hull: scuffed micro-normals; polished hole faces stay true.
                let scuff = (hash3(floor(p * 48.0)) - 0.5) * 0.35 * (1.0 - polish);
                mirror_n = normalize(n + fracture + scuff);
            }

            let spec_pow = select(64.0, mix(32.0, 240.0, polish), mat_id < 0.5);
            let spec_gain = select(1.0, mix(0.22, 1.6, polish), mat_id < 0.5);
            let spec = pow(max(dot(view_dir, refl), 0.0), spec_pow) * spec_gain;

            let ao = clamp(map(p + n * 0.5, mouse_pos, bass).x * 2.0, 0.0, 1.0);

            if (mat_id < 0.5) {
                // Obsidian material
                let base = vec3<f32>(0.02);
                col = base * dif * ao + vec3<f32>(spec) * 2.0 * ao;
            } else {
                // Coral Material
                let color_shift = u.zoom_params.x; // 0.5 default
                let a = vec3<f32>(0.5, 0.5, 0.5);
                let b = vec3<f32>(0.5, 0.5, 0.5);
                let cx = vec3<f32>(1.0, 1.0, 1.0);
                let dx = vec3<f32>(0.00, 0.33, 0.67) + color_shift;
                let coral_color = palette(fbm(p) + time * 0.1, a, b, cx, dx);

                // Idea 1 — fBm ridge veins: two coral-native frequencies are
                // collapsed around zero into narrow, branching emissive filaments.
                let vein_domain = p * vec3<f32>(3.2, 6.5, 3.2) + vec3<f32>(0.0, 0.0, -time * fluid_speed * 0.18);
                let vein_field = fbm(vein_domain) + fbm(vein_domain * 2.7 + vec3<f32>(4.1, 1.7, 8.3)) * 0.35;
                let vein_ridge = pow(1.0 - clamp(abs(vein_field) * 3.6, 0.0, 1.0), 7.0);
                let vein_color = mix(coral_color, vec3<f32>(0.65, 0.95, 1.0), 0.55);

                // Emissive glowing
                let emission = coral_color * GLOW_INTENSITY * (1.0 + bass);

                col = emission * ao + vein_color * vein_ridge * GLOW_INTENSITY * (1.2 + treble);
                ray_emission += length(emission) * 0.2 + vein_ridge;
            }

            // Idea 2 — a narrow emissive meniscus marks the smooth-min contact
            // where living coral wets the obsidian. Grazing angles sharpen it.
            let contact_band = 1.0 - smoothstep(0.018, 0.095, contact_gap);
            let grazing = pow(1.0 - abs(dot(n, view_dir)), 2.0);
            let meniscus = contact_band * (0.35 + grazing * 0.65);
            let meniscus_color = palette(
                fbm(p * 2.0) + time * 0.08,
                vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0),
                vec3<f32>(0.08, 0.40, 0.72) + u.zoom_params.x
            );
            col += meniscus_color * meniscus * GLOW_INTENSITY * (1.0 + bass * 0.35);
            ray_emission += meniscus;

            // Idea 3 — smoking mirror: obsidian is volcanic glass (n ≈ 1.49, F0 ≈ 0.04),
            // a black mirror. One short reflection march (centre ray only, shared by
            // the RGB split) brings the coral's light back off the lattice faces.
            if (mat_id < 0.5 && c == 1) {
                let cos_v = clamp(dot(mirror_n, view_dir), 0.0, 1.0);
                let fres = 0.04 + 0.96 * pow(1.0 - cos_v, 5.0);
                let mdir = reflect(-view_dir, mirror_n);
                var mt = 0.06;
                var m_glow = 0.0;
                var m_col = vec3<f32>(0.0);
                for (var j = 0; j < 12; j++) {
                    let mp = p + mirror_n * 0.02 + mdir * mt;
                    let mres = map(mp, mouse_pos, bass);
                    if (mres.y > 0.5) { m_glow += exp(-max(mres.x, 0.0) * 2.0); }
                    if (mres.x < SURF_DIST * 2.0) {
                        if (mres.y > 0.5) {
                            m_col = palette(fbm(mp) + time * 0.1, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0),
                                            vec3<f32>(0.00, 0.33, 0.67) + u.zoom_params.x) * GLOW_INTENSITY * (1.0 + bass);
                        }
                        break;
                    }
                    mt += mres.x;
                    if (mt > 14.0) { break; }
                }
                let m_glow_color = palette(time * 0.2, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0),
                                           vec3<f32>(0.0, 0.33, 0.67) + u.zoom_params.x);
                let reflected = (m_col + m_glow * 0.06 * GLOW_INTENSITY * m_glow_color) * exp(-mt * 0.08);
                // Smoky glass tint; the weathered hull only returns a dull sheen.
                // Pre-fogged with the centre ray's distance; added to all three channels after the split.
                mirror_rgb = reflected * vec3<f32>(0.85, 0.82, 0.9) * fres * mix(0.35, 1.0, polish) * 1.6
                           * (1.0 - smoothstep(0.0, MAX_DIST, t));
                ray_emission += length(mirror_rgb) * 0.3;
            }
        }

        // Volumetric glowing from coral
        let glow = dist_to_coral * 0.02 * GLOW_INTENSITY;
        let color_shift = u.zoom_params.x;
        let glow_color = palette(time * 0.2, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67) + color_shift);

        col += glow * glow_color;
        ray_emission += glow;

        // Fog based on void darkness
        col = mix(col, vec3<f32>(0.0, 0.0, 0.05) * (1.0 - VOID_DARKNESS), smoothstep(0.0, MAX_DIST, t));

        if (c == 0) { final_color.r = col.r; }
        if (c == 1) {
            final_color.g = col.g;
            center_depth = select(0.0, 1.0 - clamp(t / MAX_DIST, 0.0, 1.0), t < MAX_DIST);
            // The fogged void down the tunnel is still scene, not a hole (was alpha 0.02 → page white).
            center_coverage = select(0.85, 1.0, t < MAX_DIST);
            center_emission = ray_emission;
        }
        if (c == 2) { final_color.b = col.b; }
    }

    final_color += mirror_rgb;

    // Vignette
    final_color *= max(1.0 - length(uv) * 0.5, 0.0);

    let mapped_color = acesToneMap(max(final_color, vec3<f32>(0.0)));
    let prev = textureLoad(dataTextureC, coords, 0);
    let history_weight = select(0.0, 0.1, prev.a > 0.001);
    let display_color = mix(mapped_color, prev.rgb, history_weight);
    let emissive_coverage = 1.0 - exp(-max(center_emission, 0.0) * 0.45);
    let alpha = clamp(center_coverage * 0.92 + emissive_coverage * 0.06 + 0.02, 0.02, 1.0);

    // A stores the same ACES display RGBA read from C for restrained persistence.
    textureStore(dataTextureA, coords, vec4<f32>(display_color, alpha));
    textureStore(writeTexture, coords, vec4<f32>(display_color, alpha));
    textureStore(writeDepthTexture, coords, vec4<f32>(center_depth, 0.0, 0.0, 0.0));
}
