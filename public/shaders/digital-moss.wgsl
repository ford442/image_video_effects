// ═══════════════════════════════════════════════════════════════════
//  Digital Moss
//  Category: simulation
//  Features: mouse-driven, audio-reactive, upgraded-rgba, simulation
//  Complexity: Medium
//  Upgraded: 2026-09-12, 2026-10-25
//  Ideas: shade taxis toward darker neighbor; rhizoid threads along luma gradient; isotropic 9-point propagation + capillary moisture diffusion (§12.2D); wet/dry moisture sheen (moisture promoted from habitat-only); sporophyte seta + capsule on mature cushions (§12.1)
//  A packing: raw (grown, moisture, spores, age); texel (0,0) = inherited-state sentinel (r = -0.6875)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// Moss/Foliage Material Properties
const MOSS_DENSITY: f32 = 1.5;            // Moss is relatively light
const LEAF_SCATTERING: f32 = 1.8;         // Leaves scatter light strongly
const CHLOROPHYLL_ABSORPTION: vec3<f32> = vec3<f32>(0.7, 0.2, 0.6); // Absorbs red/blue
const DENSE_MOSS_ALPHA: f32 = 0.88;       // Thick moss is fairly opaque
const YOUNG_MOSS_ALPHA: f32 = 0.45;       // Young growth is translucent
const SCANLINE_DENSITY: f32 = 500.0;      // Digital scanline effect

fn hash12(p: vec2<f32>) -> f32 {
    var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) /
        max(x * (2.43 * x + 0.59) + 0.14, vec3<f32>(0.001)),
        vec3<f32>(0.0), vec3<f32>(1.0));
}

// Inherited-state guard: on a shader switch dataTextureC still holds the PREVIOUS shader's display RGBA (alpha 1),
// which this sim would read as moss. Texel (0,0) of A carries a sentinel; C is trusted only if it shows up there.
const SENTINEL: f32 = -0.6875;
var<private> g_valid: f32 = 1.0;

fn stateAt(p: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
    let c = clamp(p, vec2<i32>(0), dims - vec2<i32>(1));
    let isCorner = c.x == 0 && c.y == 0;     // the sentinel texel holds no moss
    return textureLoad(dataTextureC, c, 0) * select(g_valid, 0.0, isCorner);
}

// Calculate moss density/thickness from growth state
fn calculateMossThickness(growth: f32, age: f32) -> f32 {
    // Young moss is thin, mature moss is thicker
    let maturity = smoothstep(0.0, 0.8, growth);
    let baseThickness = mix(0.1, 0.4, maturity);

    // Age adds layers
    let ageThickness = age * 0.05;

    return baseThickness + ageThickness;
}

// Leaf subsurface scattering (photosynthetic tissue)
fn mossSSS(growth: f32, lightExposure: f32) -> vec3<f32> {
    // Chlorophyll absorption (green transmission)
    let chlorophyll = vec3<f32>(0.15, 0.85, 0.25);

    // Photosynthetic scattering
    let scatter = lightExposure * LEAF_SCATTERING;

    // Healthy moss has vibrant green
    let healthyColor = vec3<f32>(0.2, 0.95, 0.35);

    // Less healthy (sparse) moss is yellow-green
    let sparseColor = vec3<f32>(0.5, 0.8, 0.2);

    let healthMix = smoothstep(0.3, 0.9, growth);
    let baseColor = mix(sparseColor, healthyColor, healthMix);

    // Apply chlorophyll absorption
    return baseColor * chlorophyll * (1.0 + scatter * 0.3);
}

// Calculate alpha for moss based on growth and thickness
fn calculateMossAlpha(growth: f32, thickness: f32, scanline: f32) -> f32 {
    // Young/ sparse moss is more transparent
    let growthAlpha = mix(YOUNG_MOSS_ALPHA, DENSE_MOSS_ALPHA, growth);

    // Thickness affects opacity (Beer-Lambert)
    let opacity = 1.0 - exp(-thickness * MOSS_DENSITY);
    let thicknessAlpha = mix(YOUNG_MOSS_ALPHA, growthAlpha, opacity);

    // Digital scanline effect creates pattern in alpha
    let scanAlpha = mix(thicknessAlpha, thicknessAlpha * 0.9, scanline * 0.3);

    // Very sparse areas fade out
    let sparseFade = smoothstep(0.0, 0.15, growth);

    return clamp(scanAlpha * sparseFade + 0.2, 0.25, 0.92);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    g_valid = select(0.0, 1.0, abs(textureLoad(dataTextureC, vec2<i32>(0), 0).r - SENTINEL) < 0.001);
    var uv = (vec2<f32>(coord) + 0.5) / vec2<f32>(dims);

    // Uniforms
    let time = u.config.x;
    var mouse = u.zoom_config.yz;
    let aspect = f32(dims.x) / f32(dims.y);
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let intensity = mix(0.25, 1.8, u.zoom_params.x);
    let speed = mix(0.002, 0.035, u.zoom_params.y) * (1.0 + audio.x * 0.6);
    let scale = mix(18.0, 140.0, u.zoom_params.z);
    let detail = mix(0.15, 1.0, u.zoom_params.w);

    // Sample Image Luma
    let imgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let luma = dot(imgColor, vec3<f32>(0.299, 0.587, 0.114));

    // Sample Previous Moss State from dataTextureC
    let oldState = stateAt(coord, dims);
    var grown = oldState.r;
    var moisture = oldState.g;
    var spores = oldState.b;
    var mossAge = oldState.a;

    // 8-neighbourhood of the previous state (4 edge + 4 corner taps)
    let left = stateAt(coord + vec2<i32>(-1, 0), dims);
    let right = stateAt(coord + vec2<i32>(1, 0), dims);
    let up = stateAt(coord + vec2<i32>(0, 1), dims);
    let down = stateAt(coord + vec2<i32>(0, -1), dims);
    let ul = stateAt(coord + vec2<i32>(-1, 1), dims);
    let ur = stateAt(coord + vec2<i32>(1, 1), dims);
    let dl = stateAt(coord + vec2<i32>(-1, -1), dims);
    let dr = stateAt(coord + vec2<i32>(1, -1), dims);

    // ── Idea 1: isotropic 9-point stencil (§12.2D) — 0.2 edges / 0.05 corners (weights sum to 1, same mean as the
    // old 4-tap average) removes the axis bias that grew diamond/blocky colonies. Moisture also wicks sideways.
    let neighborGrowth = 0.2 * (left.r + right.r + up.r + down.r) + 0.05 * (ul.r + ur.r + dl.r + dr.r);
    let neighborSpores = 0.2 * (left.b + right.b + up.b + down.b) + 0.05 * (ul.b + ur.b + dl.b + dr.b);
    let neighborMoist = 0.2 * (left.g + right.g + up.g + down.g) + 0.05 * (ul.g + ur.g + dl.g + dr.g);
    moisture = mix(moisture, neighborMoist, 0.12);

    // Random seed that varies with time slightly for spontaneous growth
    let seed = hash12(floor(uv * scale) + vec2<f32>(floor(time * 3.0), 17.0));
    moisture = clamp(moisture * 0.995 + (1.0 - luma) * speed * 0.7, 0.0, 1.0);

    // 1. Spontaneous growth in very dark areas
    if (luma < 0.22 && seed > 0.992 - audio.z * 0.018) {
        spores = max(spores, 0.35 + audio.z * 0.45);
    }

    // 2. Propagation (Cellular Automata-ish)
    let habitat = smoothstep(0.68, 0.08, luma) * moisture;

    // Idea 1 — shade taxis: grow toward the darker neighbor
    let pixel = 1.0 / vec2<f32>(dims);
    let lumaL = dot(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(pixel.x, 0.0), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let lumaR = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixel.x, 0.0), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let lumaU = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, pixel.y), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let lumaDn = dot(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, pixel.y), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let darkest = min(min(lumaL, lumaR), min(lumaU, lumaDn));
    let fromShade = select(0.0, left.r, abs(lumaL - darkest) < 0.001)
        + select(0.0, right.r, abs(lumaR - darkest) < 0.001)
        + select(0.0, up.r, abs(lumaU - darkest) < 0.001)
        + select(0.0, down.r, abs(lumaDn - darkest) < 0.001);
    grown += (neighborGrowth * (1.0 - grown) + spores * 0.45 + fromShade * 0.35 * (1.0 - grown)) * speed * habitat * intensity;

    // Idea 2 — rhizoid threads along the luma gradient
    let lumaG = vec2<f32>(lumaR - lumaL, lumaU - lumaDn);
    let gLen = max(length(lumaG), 0.0001);
    let ridgeT = vec2<f32>(-lumaG.y, lumaG.x) / gLen;
    let thread = pow(abs(sin(dot(uv, ridgeT) * scale * 1.8 + hash12(floor(uv * scale)))), 10.0);
    grown += (1.0 - thread) * habitat * speed * detail * 0.22 * (1.0 - grown);

    spores = clamp(spores * 0.985 + neighborSpores * speed * detail - grown * 0.002, 0.0, 1.0);

    // 3. Environmental Decay
    // Bright light kills the moss
    if (luma > 0.6) {
        grown *= 1.0 - speed * (3.0 + luma * 4.0);
        moisture *= 0.985;
    }

    // 4. Mouse Interaction (Cleaning)
    let p_aspect = vec2<f32>(uv.x * aspect, uv.y);
    let m_aspect = vec2<f32>(mouse.x * aspect, mouse.y);
    let mouseDist = length(p_aspect - m_aspect);

    // Mouse brush size
    let clean = smoothstep(0.08, 0.0, mouseDist) * clamp(u.zoom_config.w, 0.0, 1.0);
    grown *= 1.0 - clean * 0.75;
    spores *= 1.0 - clean * 0.9;
    moisture *= 1.0 - clean * 0.55;

    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let event = u.ripples[i];
        let eventAge = time - event.z;
        if (eventAge >= 0.0 && eventAge < 2.5) {
            let q = (uv - event.xy) * vec2<f32>(aspect, 1.0);
            let ring = exp(-abs(length(q) - eventAge * 0.13) * 54.0 - eventAge * 1.1);
            spores += ring * (0.12 + audio.z * 0.25);
            moisture += ring * (0.08 + audio.y * 0.15);
        }
    }

    grown = clamp(grown, 0.0, 1.0);
    moisture = clamp(moisture, 0.0, 1.0);
    spores = clamp(spores, 0.0, 1.0);
    mossAge = clamp((mossAge + grown * speed * 0.5) * (1.0 - clean * 0.4), 0.0, 8.0);

    // Write State for next frame
    let isCorner = coord.x == 0 && coord.y == 0;
    textureStore(dataTextureA, coord, select(vec4<f32>(grown, moisture, spores, mossAge), vec4<f32>(SENTINEL, 0.0, 0.0, 0.0), isCorner));

    // Calculate moss material properties
    let mossThickness = calculateMossThickness(grown, mossAge);

    // Digital scanline effect for "digital" moss look
    let scan = 0.8 + 0.2 * sin(uv.y * SCANLINE_DENSITY * (0.35 + detail));

    // Calculate SSS color
    let lightExposure = 1.0 - luma; // Grows in dark areas
    var mossColor = mossSSS(grown, lightExposure);

    // ── Idea 2: capillary moisture sheen (moisture promoted from habitat-only) — dry cushions go yellow-grey and
    // matte, wet ones saturate and pick up a glossy film.
    let dry = 1.0 - smoothstep(0.1, 0.6, moisture);
    mossColor = mix(mossColor, vec3<f32>(0.55, 0.55, 0.32) * (0.4 + luma), dry * 0.5);
    mossColor += vec3<f32>(0.10, 0.18, 0.15) * smoothstep(0.55, 1.0, moisture) * grown;

    // Apply scanline to color
    let scannedMossColor = mossColor * scan * intensity +
        audio * vec3<f32>(0.08, 0.16, 0.1) * (grown + spores);

    // Mix based on growth with alpha calculation
    let mossAlpha = calculateMossAlpha(grown, mossThickness, scan);

    // Blend: image shows through moss based on alpha
    var finalColor = mix(imgColor, scannedMossColor, grown * mossAlpha);

    // ── Idea 3: sporophytes (§12.1 tactic 5) — mature cushions throw up a thin seta topped by a capsule. They sit on
    // a coarser grid (scale/4) so they read as stalks, are gated on grown + age, and glow with treble.
    let sg = uv * scale * 0.25;
    let sCell = floor(sg);
    let sf = fract(sg);
    let sh = hash12(sCell + vec2<f32>(7.3, 3.1));
    let sh2 = hash12(sCell + vec2<f32>(1.7, 9.2));
    let sx = 0.5 + (sh2 - 0.5) * 0.4;
    let sHeight = 0.35 + 0.5 * sh2;
    let rise = 1.0 - sf.y;                                           // uv.y points down, stalks rise toward y = 0
    let mature = smoothstep(0.65, 0.9, grown) * smoothstep(0.1, 0.6, mossAge);
    let present = step(0.88 - 0.1 * detail, sh) * mature;
    let seta = (1.0 - smoothstep(0.05, 0.09, abs(sf.x - sx))) * step(rise, sHeight);
    let capsule = 1.0 - smoothstep(0.14, 0.22, length(vec2<f32>(sf.x - sx, rise - sHeight - 0.1)));
    let sporo = present * max(seta * 0.8, capsule);
    let sporoCol = mix(vec3<f32>(0.50, 0.40, 0.18), vec3<f32>(1.0, 0.65, 0.2) * (1.0 + audio.z), capsule);
    finalColor = mix(finalColor, sporoCol, sporo * 0.85);

    let alpha = clamp(max(grown * mossAlpha + spores * 0.15, sporo * 0.9), 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(aces(max(finalColor, vec3<f32>(0.0))), alpha));

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
