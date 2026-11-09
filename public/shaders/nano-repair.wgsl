// ═══════════════════════════════════════════════════════════════
//  Nano Repair with Alpha Scattering
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, feedback, semantic-alpha
//  Upgraded: 2026-09-12
//  Upgraded: 2026-11-09
//  Ideas: healing front on |∇health|; weld flash where health rose this frame;
//         rot contagion (decay creeps from damaged neighbours); nanite swarm specks orbiting the
//         active repair zone; weld-scar lattice (A.g memory of recent repair, fades over ~3 s)
//  A packing: raw (health, scar, 0, 1); C is A from the previous frame
// ═══════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn loadHealth(coord: vec2<i32>, maxCoord: vec2<i32>) -> f32 {
    return textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), maxCoord), 0).r;
}
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Soft particle alpha
fn softParticleAlpha(dist: f32, radius: f32) -> f32 {
    let t = dist / radius;
    return exp(-t * t * 2.0);
}

// Exponential transmittance
fn transmittance(density: f32) -> f32 {
    return exp(-density);
}

// Glitch noise function
fn glitchNoise(uv: vec2<f32>, time: f32, strength: f32) -> f32 {
    let blockSize = max(1.0, 20.0 * strength);
    let blockUV = floor(uv * blockSize) / blockSize;
    return hash12(blockUV + time);
}

// Repair emission color
fn repairEmission(health: f32) -> vec3<f32> {
    // Damaged = red/orange glow, Healthy = normal
    let damaged = vec3<f32>(1.0, 0.3, 0.1);
    let healthy = vec3<f32>(0.2, 1.0, 0.4);
    return mix(damaged, healthy, health);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    let maxCoord = vec2<i32>(resolution) - vec2<i32>(1);
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mouse = u.zoom_config.yz;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params
    let radius = u.zoom_params.x;
    let decay = u.zoom_params.y;
    let glitchStr = u.zoom_params.z;
    let scanlines = u.zoom_params.w;

    let oldHealth = loadHealth(coord, maxCoord);
    var health = oldHealth;
    let hL = loadHealth(coord + vec2<i32>(-1, 0), maxCoord);
    let hR = loadHealth(coord + vec2<i32>(1, 0), maxCoord);
    let hD = loadHealth(coord + vec2<i32>(0, -1), maxCoord);
    let hU = loadHealth(coord + vec2<i32>(0, 1), maxCoord);
    // Idea 3 — rot contagion: pixels bordering damage decay faster, healthy interiors slower,
    // so rot advances as creeping fronts instead of a uniform fade (mean rate ≈ unchanged).
    let rotNear = 1.0 - (hL + hR + hD + hU) * 0.25;

    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);
    let dist = distance(uvCorrected, mouseCorrected);

    if (dist < radius) {
        health += 0.1 * (1.0 + bass * 0.4);
    } else {
        health -= decay * 0.01 * (0.6 + 0.8 * rotNear);
    }
    health = clamp(health, 0.0, 1.0);

    // Idea 5 — weld-scar memory: spikes where health rose, decays ~3 s
    let healedNow = clamp(health - oldHealth, 0.0, 1.0);
    let prevScar = textureLoad(dataTextureC, coord, 0).g;
    let scar = clamp(max(healedNow * 12.0, prevScar * 0.985), 0.0, 1.0);
    textureStore(dataTextureA, global_id.xy, vec4<f32>(health, scar, 0.0, 1.0));

    // ═══════════════════════════════════════════════════════════════
    //  RENDER WITH ALPHA SCATTERING
    // ═══════════════════════════════════════════════════════════════

    // Sample base texture
    var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Repair glow alpha
    let repair_radius = radius * (1.0 + sin(time * 3.0) * 0.1);
    let dist_to_repair = max(0.0, dist - radius * 0.5);
    let repair_alpha = softParticleAlpha(dist_to_repair, repair_radius) * (1.0 - health);
    
    // Idea 1 — healing front: emission on |∇health|
    let gradH = length(vec2<f32>(hR - hL, hU - hD));
    let front = smoothstep(0.04, 0.22, gradH);

    // Idea 2 — weld flash where health rose this frame
    let healed = healedNow;
    let weld = pow(healed * 8.0, 1.6) * (0.55 + mids * 0.45);

    let repair_emission = repairEmission(health);
    let repair_glow = repair_emission * (repair_alpha * 2.0 + front * 1.4);
    let weld_color = vec3<f32>(0.55, 0.95, 1.0) * weld;

    // Glitch Effect for damaged areas
    var glitch_color = color;
    var glitch_alpha: f32 = 0.0;
    
    if (health < 1.0) {
        let noiseVal = glitchNoise(uv, time, glitchStr);
        
        // Random offset blocks
        if (noiseVal > 0.8) {
             let offset = (noiseVal - 0.9) * 0.5 * glitchStr;
             glitch_color = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(offset, 0.0), 0.0).rgb;
             glitch_color.r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(offset + 0.01, 0.0), 0.0).r;
             glitch_color.b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(offset - 0.01, 0.0), 0.0).b;
             glitch_alpha = (noiseVal - 0.8) * 5.0 * (1.0 - health);
        }

        // Noise overlay
        // Zero-mean grain (was 0..+glitch, which washed damaged areas toward white)
        let grain = (hash12(uv * resolution + time) - 0.5) * glitchStr * 0.6 * (1.0 + treble * 0.3);
        glitch_color += vec3<f32>(grain);
        
        // Scanlines
        let sl = sin(uv.y * resolution.y * 0.5) * 0.5 + 0.5;
        let scanline_alpha = sl * scanlines * (1.0 - health);
        glitch_color *= mix(vec3<f32>(1.0), vec3<f32>(sl), scanline_alpha);
    }

    // Mix based on health with alpha blending
    let mask = smoothstep(0.2, 0.8, health);
    let mixed_color = mix(glitch_color, color, mask);
    
    // Idea 4 — nanite swarm: specks orbiting the cursor, only while they are still repairing
    let rel = (uvCorrected - mouseCorrected) / max(radius, 1e-3);
    let ang = atan2(rel.y, rel.x) + time * (1.2 + mids * 0.8);
    let rr = length(rel);
    let cellA = floor(ang / 6.2831853 * 28.0);
    let cellR = floor(rr * 6.0);
    let jitter = hash12(vec2<f32>(cellA, cellR));
    let fa = fract(ang / 6.2831853 * 28.0) - 0.5;
    let fr = fract(rr * 6.0) - jitter;
    let speck = exp(-(fa * fa + fr * fr) * 60.0) * step(0.55, jitter)
              * (1.0 - smoothstep(0.9, 1.3, rr)) * step(oldHealth, 0.995);
    let swarm = vec3<f32>(0.6, 1.0, 0.85) * speck * 0.9;

    // Idea 5 — weld-scar lattice: faint hex-ish seam grid where repair recently happened
    let g = uv * resolution / 9.0;
    let gl = abs(fract(g + vec2<f32>(0.5 * floor(g.y), 0.0)) - 0.5);
    let lattice = (1.0 - smoothstep(0.0, 0.08, min(gl.x, gl.y))) * scar * health;
    let scar_color = vec3<f32>(0.35, 0.8, 0.9) * lattice * 0.35;

    let final_color = mixed_color + repair_glow + weld_color + swarm + scar_color;
    
    // Cumulative alpha from damage and repair
    let damage_density = (1.0 - health) * (glitch_alpha + scanlines * 0.3);
    let repair_density = repair_alpha * health;
    let total_density = damage_density + repair_density;
    
    // Exponential transmittance
    let trans = transmittance(total_density);
    // Rescue: alpha was ~0 on healed image (composited away). Now opacity = image coverage,
    // thinned by damage density; front/weld/specks stay fully opaque.
    let cumulative_alpha = clamp(1.0 - 0.45 * (1.0 - trans) + front * 0.25 + weld * 0.35 + speck, 0.4, 1.0);
    
    let hdr_color = acesToneMap(final_color * (1.0 + repair_alpha + weld * 0.4));

    let output = vec4<f32>(hdr_color, cumulative_alpha);
    textureStore(writeTexture, vec2<i32>(global_id.xy), output);
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
