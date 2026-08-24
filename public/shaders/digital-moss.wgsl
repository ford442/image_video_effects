// ═══════════════════════════════════════════════════════════════
//  Digital Moss - Simulation with Organic Foliage Material Properties
//  Category: simulation
//  Features: Moss growth, leaf translucency, photosynthetic tissue
// ═══════════════════════════════════════════════════════════════

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var filteringSampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

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

fn stateAt(p: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
    return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), dims - vec2<i32>(1)), 0);
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

    // Random seed that varies with time slightly for spontaneous growth
    let seed = hash12(floor(uv * scale) + vec2<f32>(floor(time * 3.0), 17.0));
    moisture = clamp(moisture * 0.995 + (1.0 - luma) * speed * 0.7, 0.0, 1.0);

    // 1. Spontaneous growth in very dark areas
    if (luma < 0.22 && seed > 0.992 - audio.z * 0.018) {
        spores = max(spores, 0.35 + audio.z * 0.45);
    }

    // 2. Propagation (Cellular Automata-ish)
    let left = stateAt(coord + vec2<i32>(-1, 0), dims);
    let right = stateAt(coord + vec2<i32>(1, 0), dims);
    let up = stateAt(coord + vec2<i32>(0, 1), dims);
    let down = stateAt(coord + vec2<i32>(0, -1), dims);
    let neighborGrowth = (left.r + right.r + up.r + down.r) * 0.25;
    let neighborSpores = (left.b + right.b + up.b + down.b) * 0.25;
    let habitat = smoothstep(0.68, 0.08, luma) * moisture;
    grown += (neighborGrowth * (1.0 - grown) + spores * 0.45) * speed * habitat * intensity;
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
    textureStore(dataTextureA, coord, vec4<f32>(grown, moisture, spores, mossAge));

    // Calculate moss material properties
    let mossThickness = calculateMossThickness(grown, mossAge);

    // Digital scanline effect for "digital" moss look
    let scan = 0.8 + 0.2 * sin(uv.y * SCANLINE_DENSITY * (0.35 + detail));

    // Calculate SSS color
    let lightExposure = 1.0 - luma; // Grows in dark areas
    let mossColor = mossSSS(grown, lightExposure);

    // Apply scanline to color
    let scannedMossColor = mossColor * scan * intensity +
        audio * vec3<f32>(0.08, 0.16, 0.1) * (grown + spores);

    // Mix based on growth with alpha calculation
    let mossAlpha = calculateMossAlpha(grown, mossThickness, scan);

    // Blend: image shows through moss based on alpha
    let finalColor = mix(imgColor, scannedMossColor, grown * mossAlpha);

    let alpha = clamp(grown * mossAlpha + spores * 0.15, 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(aces(finalColor), alpha));

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, filteringSampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
