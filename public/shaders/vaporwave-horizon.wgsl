// ═══════════════════════════════════════════════════════════════════
//  Vaporwave Horizon
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-10
//  Ideas: striped retro sun on the horizon; two-tone neon line bloom; mirror floor reflects the displayed sky
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
//  Scientific Implementation (kept from HEAD):
//  - Distance-based fog with optical depth
//  - Atmospheric perspective using Beer-Lambert law
//  - Grid rendered as emissive surface with volumetric fog overlay
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// Atmospheric extinction coefficients
const SIGMA_T_ATMOSPHERE: f32 = 0.6;    // Atmospheric extinction
const SIGMA_T_FOG: f32 = 1.2;           // Purple fog extinction

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Idea 1: striped retro sun. Disc centred on the horizon (screen-space,
// aspect-correct). Lower half is cut by horizontal bands whose gap thickens
// toward the base and scrolls downward with the grid. Returns (rgb, coverage).
fn retro_sun(uv: vec2<f32>, horizon: f32, aspect: f32, radius: f32, scroll: f32) -> vec4<f32> {
    let c = vec2<f32>(0.5, horizon - radius * 0.7);
    let p = vec2<f32>((uv.x - c.x) * aspect, uv.y - c.y);
    let r = length(p);
    let disc = 1.0 - smoothstep(radius - 0.004, radius + 0.004, r);
    // h: 0 at the disc centre, 1 at its bottom edge (y-down screen).
    let h = clamp(p.y / radius, 0.0, 1.0);
    let band = fract(p.y * 18.0 / radius - scroll);
    let gap = h * 0.75;                       // gaps widen toward the base
    let cut = select(1.0, smoothstep(gap - 0.06, gap + 0.06, band), p.y > 0.0);
    let top = vec3<f32>(1.0, 0.86, 0.25);
    let bot = vec3<f32>(1.0, 0.18, 0.55);
    let t = clamp(p.y / radius * 0.5 + 0.5, 0.0, 1.0);
    let col = mix(top, bot, t) * 1.6;
    let cov = disc * cut;
    // soft corona outside the disc
    let corona = exp(-max(r - radius, 0.0) * 14.0) * (1.0 - disc) * 0.35;
    return vec4<f32>(col * cov + bot * corona, max(cov, corona));
}

// Sky = squashed photo + Beer-Lambert sunset haze + sun. Shared by the floor
// reflection (idea 3) so the mirror shows exactly what is drawn above.
fn sky_color(uv: vec2<f32>, horizon: f32, aspect: f32, glow: f32, sunR: f32, scroll: f32) -> vec4<f32> {
    let sky_uv_y = clamp(uv.y / max(horizon, 0.01), 0.0, 1.0);
    let img_color = textureSampleLevel(readTexture, u_sampler, vec2<f32>(uv.x, sky_uv_y), 0.0).rgb;
    let gradient = smoothstep(0.0, 1.0, sky_uv_y);
    let sunset_color = vec3<f32>(0.8, 0.2, 0.5);
    let heightFactor = 1.0 - sky_uv_y;
    let opticalDepth = heightFactor * 0.5 * SIGMA_T_ATMOSPHERE;
    let transmittance = exp(-opticalDepth);
    var col = mix(img_color * transmittance, sunset_color, gradient * 0.3 * glow * (1.0 - transmittance));
    let sun = retro_sun(uv, horizon, aspect, sunR, scroll);
    let sunMix = sun.a * clamp(0.45 + 0.35 * glow, 0.0, 1.0);
    col = mix(col, sun.rgb, sunMix);
    return vec4<f32>(col, sunMix);
}

// Idea 2: distance-filtered neon line — bright core plus soft halo.
// d = distance to the line in cell units, w = pixel footprint in cell units.
fn neon_line(d: f32, w: f32) -> vec2<f32> {
    let core = 1.0 - smoothstep(0.03, 0.03 + max(w, 0.002) * 1.5, d);
    let halo = exp(-d / max(0.045 + w * 2.0, 1e-3));
    return vec2<f32>(core, halo);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let aspect = resolution.x / resolution.y;

    // Audio: bass pumps sun + line halo, mids glows the lines, treble warps the curve
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Parameters (roles kept). Bass no longer multiplies grid speed: inside
    // time*speed it made the grid jump by whole cells at large t.
    let grid_speed = u.zoom_params.x;
    let glow_intensity = u.zoom_params.y * (1.0 + mids * 0.7);
    let grid_scale = u.zoom_params.z;
    let warp_amt = u.zoom_params.w * (1.0 + treble * 0.4);

    // Mouse Interaction
    let horizon = u.zoom_config.z;
    let mouse_x = u.zoom_config.y;
    let curve = (mouse_x - 0.5) * 4.0 * warp_amt;

    let sunR = 0.17 * (1.0 + bass * 0.12);
    let sunScroll = u.config.x * grid_speed * 0.6;

    var final_color = vec3<f32>(0.0);
    var alpha = 0.0;

    if (uv.y < horizon) {
        // SKY: photo + haze + striped sun
        let sky = sky_color(uv, horizon, aspect, glow_intensity, sunR, sunScroll);
        final_color = sky.rgb;
        // transmission-ish alpha: photo sky slightly see-through, sun opaque
        alpha = mix(0.92, 1.0, sky.a);
    } else {
        // FLOOR: perspective grid
        let dy = uv.y - horizon;
        let z_depth = 1.0 / max(dy, 0.001);

        let x_offset = curve * dy * dy;
        let gs = 0.5 + grid_scale;
        let grid_u = (uv.x - 0.5 - x_offset) * z_depth * gs + 0.5;
        let grid_v = z_depth * gs + u.config.x * grid_speed + bass * 0.08;

        // Pixel footprint in cell units (analytic derivatives of the mapping)
        let px = 1.0 / resolution;
        let wu = abs(z_depth * gs) * px.x + abs((uv.x - 0.5 - x_offset) * gs * z_depth * z_depth) * px.y;
        let wv = abs(gs * z_depth * z_depth) * px.y;

        let du = abs(fract(grid_u) - 0.5);
        let dv = abs(fract(grid_v) - 0.5);
        // distance from the cell edge (HEAD: step(0.45, |fract-0.5|))
        let lu = neon_line(0.5 - du, wu);
        let lv = neon_line(0.5 - dv, wv);

        // Idea 2: two-tone — cyan longitudes, magenta latitudes; halo glows.
        let cyan = vec3<f32>(0.0, 1.0, 1.0);
        let magenta = vec3<f32>(1.0, 0.15, 0.85);
        let haloGain = 0.22 * (1.0 + bass * 0.6);
        let grid_val = clamp(max(lu.x, lv.x), 0.0, 1.0);
        let grid_col = (cyan * (lu.x + lu.y * haloGain) + magenta * (lv.x + lv.y * haloGain)) * glow_intensity * 1.6;

        // Idea 3: mirror floor reflects the displayed sky (photo squash + sun),
        // rippled slightly by the grid cells so it reads as a wet floor.
        let refl_y = horizon - dy;
        let ripple = sin(grid_v * 6.2831) * 0.004 * min(dy * 4.0, 1.0);
        let refl = sky_color(vec2<f32>(uv.x + ripple, clamp(refl_y, 0.0, horizon)), horizon, aspect, glow_intensity, sunR, sunScroll).rgb;

        let fade = smoothstep(0.0, 0.2, dy);
        // Halo fades with distance (lines merge at the horizon)
        let haloFade = mix(0.25, 1.0, fade);
        var floor_color = refl * 0.5 + grid_col * mix(fade, haloFade, 0.5);
        floor_color = mix(floor_color, grid_col, grid_val * fade * 0.6);

        // Volumetric distance fog (HEAD)
        let fogDensity = 0.15;
        let fogDistance = z_depth * 0.3;
        let fogOpticalDepth = fogDensity * fogDistance * SIGMA_T_FOG;
        let fogTransmittance = exp(-fogOpticalDepth);
        let fogColor = vec3<f32>(0.4, 0.1, 0.4);
        final_color = mix(fogColor, floor_color, fogTransmittance);

        // Alpha: fog density + emissive line coverage
        alpha = clamp(0.8 + (1.0 - fogTransmittance) * 0.2 + grid_val * 0.1, 0.0, 1.0);
    }

    let rgb = acesToneMap(max(final_color, vec3<f32>(0.0)));
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(rgb, alpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(rgb, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
