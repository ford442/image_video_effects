// ═══════════════════════════════════════════════════════════════════
//  Bioluminescent Neural Lattice
//  Category: generative
//  Features: audio-reactive, mouse-driven, temporal-feedback, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-27, 2026-10-25
//  Ideas: bass-triggered synapse firing pulses race along the lattice edges;
//         bioluminescent afterglow via real dataTextureA/C temporal memory;
//         treble shimmer on the closest-approach ambient glow; 2nd pass
//         (2026-10-25): soft inverse-square soma glow at each cell seed (§12.2F);
//         energy-conserving afterglow diffusion from exact C taps (§12.2F);
//         refractory period damps re-firing of just-lit regions (§12.1 history).
//         HEAD fixes: 180°-rotated camera basis vs cursor; mouse anchor left
//         behind by the flying camera.
//  A packing: display RGBA (afterglow-blended), C read back for temporal memory
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
// zoom_params: .x = Point Density, .y = Rotation Speed, .z = Point Size, .w = Color Shift

// --- CONSTANTS ---
const MAX_STEPS: i32 = 80;
const MAX_DIST: f32 = 20.0;
const SURF_DIST: f32 = 0.01;
const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// --- UTILS ---
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// Smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 3D Voronoi edges (cellular noise variation)
fn voronoi_edges(p: vec3<f32>, t: f32) -> f32 {
    let n = floor(p);
    let f = fract(p);

    var res = 8.0;

    for (var k = -1; k <= 1; k++) {
        for (var j = -1; j <= 1; j++) {
            for (var i = -1; i <= 1; i++) {
                let b = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash33(n + b);

                // Animate points
                let anim_o = 0.5 + 0.5 * sin(t + 6.2831 * o);
                let r = b - f + anim_o;

                let d = dot(r, r);
                if (d < res) {
                    res = d;
                }
            }
        }
    }

    return sqrt(res);
}

// Same as voronoi_edges, but also returns a stable per-cell hash id (.y) so the
// caller can phase a "firing" signal differently per synapse cluster.
fn voronoi_edges_id(p: vec3<f32>, t: f32) -> vec2<f32> {
    let n = floor(p);
    let f = fract(p);

    var res = 8.0;
    var idh = 0.0;

    for (var k = -1; k <= 1; k++) {
        for (var j = -1; j <= 1; j++) {
            for (var i = -1; i <= 1; i++) {
                let b = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash33(n + b);

                let anim_o = 0.5 + 0.5 * sin(t + 6.2831 * o);
                let r = b - f + anim_o;

                let d = dot(r, r);
                if (d < res) {
                    res = d;
                    idh = o.x;
                }
            }
        }
    }

    return vec2<f32>(sqrt(res), idh);
}

// --- SDF ---
// Returns .x = surface distance, .y = combined voronoi value (for palette), .z = fire pulse (Idea 1)
fn map(p_in: vec3<f32>, time: f32, bass: f32, u_zoom: vec4<f32>) -> vec3<f32> {
    var p = p_in;
    let synapse_density = u_zoom.x;
    let pulse_speed = u_zoom.y;

    // Mouse attraction
    var mouse = u.zoom_config.yz * 2.0 - 1.0;
    mouse.y *= -1.0;

    // Simple projection of mouse into scene space at some depth
    // HEAD fix: the camera flies at 0.5/s, so the anchor rides 3 units ahead of it
    // (it used to sit at world z=3 and the pull faded after ~10 s).
    let mouse_pos = vec3<f32>(mouse.x * 2.0, mouse.y * 2.0, 2.0 + time * 0.5);

    // Warp space towards mouse slightly
    let dist_to_mouse = length(p - mouse_pos);
    let influence = exp(-dist_to_mouse * 0.5);
    p = mix(p, mouse_pos, influence * 0.2);

    // Space repetition
    p = p * synapse_density;

    // Base time for movement
    let t = time * pulse_speed * 0.2;

    // Create the lattice from voronoi
    let v1 = voronoi_edges_id(p, t);
    let d2 = voronoi_edges(p + vec3<f32>(1.5, 0.5, -0.5), t * 1.1);

    // Combine and scale back
    let combined = smin(v1.x, d2, 0.5);

    // Distance to network structure
    var base_dist = (0.7 - combined) / synapse_density;

    // Idea 1: bass-triggered synapse firing. Each lattice cell gets its own phase
    // offset (v1.y), and the phase is swept by raymarch depth (p.z) so a firing
    // event reads as a narrow bright flash racing along the tunnel rather than a
    // uniform blink. Loudness both speeds up firing and brightens the flash.
    let fire_speed = pulse_speed * (1.0 + bass * 1.2);
    let fire_phase = fract(time * fire_speed * 0.6 - p.z * 0.12 + v1.y * 6.0);
    let fire_pulse = pow(max(sin(PI * fire_phase), 0.0), 10.0) * clamp(bass * 1.5, 0.0, 1.0);
    base_dist -= fire_pulse * 0.15 / synapse_density;

    return vec3<f32>(base_dist, combined, fire_pulse);
}

// Branchless cosine palette
fn palette(t: f32, color_shift: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    // Deep cyan to electric blue/magenta
    let c = vec3<f32>(1.0, 1.0, 0.5);
    let d = vec3<f32>(0.00, 0.33, 0.67) + color_shift;

    return a + b * cos(TAU * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    let id = vec2<i32>(global_id.xy);
    let dims_i32 = vec2<i32>(dimensions);

    if (id.x >= dims_i32.x || id.y >= dims_i32.y) {
        return;
    }

    let time = u.config.x;
    let res = vec2<f32>(f32(dimensions.x), f32(dimensions.y));
    let base_uv = vec2<f32>(id) / res;
    let uv = (vec2<f32>(id) - 0.5 * res) / res.y;

    // Params
    let u_zoom = u.zoom_params;
    let glow_intensity = u_zoom.z;
    let color_shift = u_zoom.w;

    // Real audio reactivity (bass drives firing + camera shake, mids drive the
    // ambient pulse, treble drives the closest-approach shimmer below).
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Camera
    var ro = vec3<f32>(0.0, 0.0, -1.0 + time * 0.5);
    var ta = ro + vec3<f32>(0.0, 0.0, 1.0);

    // Very slight camera shake from bass
    ro += vec3<f32>(sin(time * 10.0), cos(time * 11.0), 0.0) * bass * 0.02;

    // Camera matrix
    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = cross(cu, cw);
    // HEAD fix: cu = -x and cv = +y with uv.y pointing down gave a 180° rotated view,
    // so the cursor warp sat opposite the pointer. Right = +x, up = +y now.
    let rd = normalize(-uv.x * cu - uv.y * cv + 1.5 * cw);

    // Raymarching
    var d0 = 0.0;
    var p = vec3<f32>(0.0);
    var glow = vec3<f32>(0.0);
    var fire_glow = vec3<f32>(0.0);
    var min_dist = 100.0;

    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * d0;
        let map_res = map(p, time, bass, u_zoom);
        let d = map_res.x;

        // Track minimum distance for glow
        if (d < min_dist) {
            min_dist = d;
        }

        // Volumetric accumulation
        let glow_factor = exp(-d * 4.0);

        // Base color maps to the structure value (map_res.y)
        var col_val = palette(map_res.y * 2.0 + time * 0.1, color_shift);

        // Ambient synapse hum, now keyed to mids so it reads distinctly from
        // the sharper bass-triggered firing pulses below
        let pulse = sin(p.z * 10.0 - time * 20.0) * 0.5 + 0.5;
        col_val += vec3<f32>(0.2, 0.5, 1.0) * pulse * mids * 2.0;

        glow += col_val * glow_factor * 0.03 * glow_intensity;

        // Idea 1 (continued): render the firing pulse as a bright cyan-white
        // spark, distinct from the palette-driven ambient glow above
        fire_glow += vec3<f32>(0.6, 0.9, 1.0) * map_res.z * glow_factor * 0.05;

        // Idea 4 (2nd pass A): soft inverse-square soma glow (§12.2F). map_res.y is the
        // distance to the nearest cell seed, so each nucleus is a point light with a core
        // radius (no singularity). Cheap: reuses the value map() already returned.
        let soma = 0.012 / (map_res.y * map_res.y + 0.18);
        glow += col_val * soma * glow_factor * glow_intensity;

        // Step forward
        d0 += max(d * 0.8, 0.01);

        if (d < SURF_DIST || d0 > MAX_DIST) {
            break;
        }
    }

    // Background: dark oceanic void
    var bg_col = vec3<f32>(0.01, 0.05, 0.1);

    // Depth fog
    let fog = 1.0 - exp(-d0 * 0.1);

    // Idea 6 (2nd pass C): refractory period. A region that was just lit hard cannot flash
    // again at full strength, so bursts read as travelling pulses instead of strobing.
    let prevA = textureLoad(dataTextureC, id, 0);
    let prevLuma = dot(prevA.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
    let refractory = 1.0 - 0.45 * smoothstep(0.45, 0.85, prevLuma);

    // Final composite
    var col = mix(glow + fire_glow * refractory, bg_col, fog);

    // Idea 3: treble-driven shimmer on the ambient closest-approach glow
    let ambient = palette(min_dist, color_shift) * exp(-min_dist * 2.0) * glow_intensity;
    col += ambient * 0.2 * (1.0 + treble * 0.6);

    // Tone mapping (simple exposure/ACES fit approx)
    col = col * 1.5;
    col = col / (1.0 + col);

    // Idea 2: bioluminescent afterglow. dataTextureA/C now carry the real
    // display history (previously a dead binding), so recently-lit regions
    // keep a decaying glow rather than vanishing the instant the ray moves on.
    // Idea 5 (2nd pass B): energy-conserving afterglow diffusion (§12.2F bloom row). The
    // remembered light spreads to its neighbours with weights summing to 1, like
    // dinoflagellate light diffusing through water: it softens, it never gains energy.
    let cmax = dims_i32 - vec2<i32>(1);
    let gN = textureLoad(dataTextureC, clamp(id + vec2<i32>(0, -2), vec2<i32>(0), cmax), 0).rgb;
    let gS = textureLoad(dataTextureC, clamp(id + vec2<i32>(0, 2), vec2<i32>(0), cmax), 0).rgb;
    let gE = textureLoad(dataTextureC, clamp(id + vec2<i32>(2, 0), vec2<i32>(0), cmax), 0).rgb;
    let gW = textureLoad(dataTextureC, clamp(id + vec2<i32>(-2, 0), vec2<i32>(0), cmax), 0).rgb;
    let prevSoft = prevA.rgb * 0.5 + (gN + gS + gE + gW) * 0.125;
    let afterglow_decay = clamp(0.78 + glow_intensity * 0.08, 0.7, 0.95);
    let trailed = max(col, prevSoft * afterglow_decay);

    let lum = dot(trailed, vec3<f32>(0.2126, 0.7152, 0.0722));
    let alpha = clamp(lum * 1.4, 0.15, 1.0);

    textureStore(writeTexture, id, vec4<f32>(trailed, alpha));
    textureStore(dataTextureA, id, vec4<f32>(trailed, alpha));

    let depth_norm = clamp(d0 / MAX_DIST, 0.0, 1.0);
    textureStore(writeDepthTexture, id, vec4<f32>(depth_norm, 0.0, 0.0, 0.0));
}
