// Lenia-inspired continuous cellular field with advected growth packets.
//  Rescue: 2026-10-05 — HEAD stored smoothstep(threshold) of the field as the state, so a dead
//          cell could never reach the cutoff and a live one never left it: frozen binary stamps
//          that only the mouse could add. The state is now the continuous field (Lenia proper:
//          3-peak ring kernel, Gaussian growth, dt); the threshold is applied for display only.
//          A little viscosity stops the discrete kernel's negative lobes from growing speckle;
//          empty neighbourhoods re-seed. Ranges are numpy-gated (scripts/sim_models/lenia_rescue.py)
//          so every slider position keeps the field alive without flooding.
//  A packing: (field, growth, display trail, 1 = initialised)

#include "_prelude.wgsl"

// Relative heights of the kernel's three concentric rings.
const PEAKS = vec3<f32>(0.5, 1.0, 0.667);

fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(p.x * 127.1 + p.y * 311.7) * 43758.5453);
}

fn wrapLoad(pixel: vec2<i32>, size: vec2<i32>) -> vec4<f32> {
    return textureLoad(dataTextureC, (pixel % size + size) % size, 0);
}

// Smooth bump on each of the three rings of radius r ∈ (0, 1).
fn kernelWeight(r: f32) -> f32 {
    if (r <= 0.0 || r >= 1.0) { return 0.0; }
    let br = r * 3.0;
    let ring = min(u32(br), 2u);
    let f = fract(br);
    if (f <= 0.0) { return 0.0; }
    return PEAKS[ring] * exp(4.0 - 1.0 / (f * (1.0 - f)));
}

// Smooth noise at about half the kernel radius (per-pixel noise freezes into speckle).
fn smoothNoise(p: vec2<f32>, epoch: f32, radius: f32) -> f32 {
    let k = 1.6 / radius;
    return 0.5 + 0.25 * (sin(p.x * k * 1.3 + epoch * 1.7 + sin(p.y * k * 0.9))
                       + sin(p.y * k * 1.1 - epoch * 2.3 + sin(p.x * k * 0.7)));
}

// Smooth blob in a cell of size `cell` px, or 0. `epoch` decorrelates re-seeds.
fn blob(p: vec2<f32>, cell: f32, epoch: f32, radius: f32) -> f32 {
    let c = floor(p / cell);
    let jitter = vec2<f32>(hash2(c + vec2<f32>(epoch, 3.0)), hash2(c + vec2<f32>(1.0, epoch + 9.0)));
    let centre = (c + 0.25 + 0.5 * jitter) * cell;
    let d = length(p - centre) / (cell * 0.32);
    if (d >= 1.0) { return 0.0; }
    return clamp(smoothNoise(p, epoch, radius) * (1.0 - d * d) * 1.2, 0.0, 1.0);
}

// First-frame state: blobs in about 80% of the cells.
fn seedField(p: vec2<f32>, cell: f32, radius: f32) -> f32 {
    if (hash2(floor(p / cell)) <= 0.2) { return 0.0; }
    return blob(p, cell, 0.0, radius);
}

fn fieldAt(pixel: vec2<i32>, size: vec2<i32>, cell: f32, radius: f32) -> f32 {
    let s = wrapLoad(pixel, size);
    return select(seedField(vec2<f32>(pixel), cell, radius), s.r, s.a > 0.5);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let size = vec2<i32>(textureDimensions(dataTextureC));
    let p = vec2<f32>(coord);
    let uv = (p + 0.5) / resolution;
    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;

    let radius = 8.0 + u.zoom_params.x * 3.5;
    let dt = (0.05 + u.zoom_params.y * 0.10) * (1.0 + audio.x * 0.35);
    let accumulation = u.zoom_params.z;
    let mu = (0.135 + u.zoom_params.w * 0.035) * (1.0 - audio.z * 0.03);
    let sigma = mu * 0.094;
    let threshold = mix(0.18, 0.72, u.zoom_params.w);
    let cell = 2.6 * radius;

    let prev = wrapLoad(coord, size);
    // C starts at zero; alpha marks texels this shader has written. Seed blobs on first use.
    let initialised = prev.a > 0.5;
    let centre = select(seedField(p, cell, radius), prev.r, initialised);
    let trailPrev = select(0.0, prev.b, initialised);

    // Ring-kernel potential over the previous field (radius ≤ 11.5: at most 23² taps).
    let reach = i32(ceil(radius));
    var potential = 0.0;
    var weightSum = 0.0;
    for (var y = -reach; y <= reach; y = y + 1) {
        for (var x = -reach; x <= reach; x = x + 1) {
            let w = kernelWeight(length(vec2<f32>(f32(x), f32(y))) / radius);
            if (w <= 0.0) { continue; }
            potential += w * fieldAt(coord + vec2<i32>(x, y), size, cell, radius);
            weightSum += w;
        }
    }
    potential = potential / max(weightSum, 1e-4);

    // Viscosity: half-way to the 4-neighbour mean.
    let neighbours = fieldAt(coord + vec2<i32>(1, 0), size, cell, radius)
        + fieldAt(coord - vec2<i32>(1, 0), size, cell, radius)
        + fieldAt(coord + vec2<i32>(0, 1), size, cell, radius)
        + fieldAt(coord - vec2<i32>(0, 1), size, cell, radius);
    var field = mix(centre, neighbours * 0.25, 0.5);

    let growth = 2.0 * exp(-0.5 * pow((potential - mu) / sigma, 2.0)) - 1.0;

    // Growth packets: travelling bands of nutrient.
    let packetPhase = dot(uv, vec2<f32>(0.846, 0.533)) * (18.0 + radius) - time * (5.0 + u.zoom_params.y * 10.0);
    let growthPacket = pow(0.5 + 0.5 * sin(packetPhase), 12.0) * (0.006 + audio.y * 0.02);

    var clickFront = 0.0;
    let aspect = resolution.x / resolution.y;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 3.0) {
            let ring = abs(length((uv - ripple.xy) * vec2<f32>(aspect, 1.0)) - age * (0.16 + audio.x * 0.08));
            clickFront += (1.0 - smoothstep(0.0, 0.025, ring)) * (1.0 - age / 3.0);
        }
    }

    let mouseDist = length((uv - u.zoom_config.yz) * vec2<f32>(aspect, 1.0));
    let inoculation = smoothstep(0.11, 0.0, mouseDist) * step(0.5, u.zoom_config.w) * 0.32;

    field = clamp(field + dt * growth + growthPacket + clickFront * 0.10 + inoculation, 0.0, 1.0);

    // Spores: an empty neighbourhood re-seeds a blob in most cells about every 3 s, so the
    // field cannot die out for good at any slider position.
    let cellId = floor(p / cell);
    let sporePhase = time / 3.0 + hash2(cellId + vec2<f32>(5.0, 2.0));
    let epoch = floor(sporePhase);
    let fires = hash2(cellId + vec2<f32>(epoch * 13.1, -epoch * 7.7)) > 0.3 && fract(sporePhase) < 0.05;
    if (fires && potential < 0.03) {
        field = max(field, blob(p, cell, epoch, radius));
    }

    // Display: threshold the continuous field; trails remember where it was.
    let finalValue = smoothstep(threshold * 0.5, max(threshold, 0.01), field);
    let trail = max(finalValue, trailPrev * (0.80 + 0.18 * accumulation));
    let species = vec3<f32>(
        smoothstep(threshold * 0.42, threshold * 0.90, field),
        smoothstep(threshold * 0.50, threshold, field),
        smoothstep(threshold * 0.58, threshold * 1.10, field)
    );
    let hue = 0.55 + 0.45 * sin(vec3<f32>(0.0, 2.094, 4.188) + finalValue * 3.14159 + audio * 2.0);
    let growthTint = vec3<f32>(0.10, 0.35, 0.45) * max(growth, 0.0) * smoothstep(0.02, 0.2, field);
    let trailTint = vec3<f32>(0.25, 0.12, 0.40) * trail * (1.0 - finalValue) * accumulation;
    let color = species * hue + growthTint + trailTint + clickFront * vec3<f32>(0.25, 0.12, 0.05);
    let alpha = clamp(max(finalValue, trail * 0.7) + clickFront * 0.15 + inoculation, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(dataTextureA, coord, vec4<f32>(field, growth, trail, 1.0));
    textureStore(writeTexture, coord, vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(1.0)), alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
