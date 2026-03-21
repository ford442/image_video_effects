// ----------------------------------------------------------------
// Cymatic Plasma-Mandalas
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Symmetry Order, y=Plasma Density, z=Cymatic Frequency, w=Swirl Chaos
    ripples: array<vec4<f32>, 50>,
};

// --- POLAR REPETITION & FOLDING ---
fn fold(uv: vec2<f32>, symmetryOrder: f32) -> vec2<f32> {
    let radius = length(uv);
    let angle = atan2(uv.y, uv.x);
    let sector = 6.2831853 / symmetryOrder;
    let foldedAngle = angle - sector * floor((angle + sector * 0.5) / sector);
    return vec2<f32>(cos(foldedAngle), sin(foldedAngle)) * radius;
}

// --- SHAPE SDFS ---
fn sdPolygon(p: vec2<f32>, sides: f32) -> f32 {
    let a = atan2(p.y, p.x);
    let b = 6.2831853 / sides;
    let modA = a - b * floor((a + b * 0.5) / b);
    return length(p) * cos(modA);
}

fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
    return length(p) - r;
}

// --- COLOR AND EFFECTS ---
fn getPalette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    return a + b * cos(6.28318 * (c * t + d));
}

fn applyChromaticAberration(distR: f32, distG: f32, distB: f32, density: f32) -> vec3<f32> {
    let plasmaR = exp(-abs(distR) * (20.0 / density));
    let plasmaG = exp(-abs(distG) * (20.0 / density));
    let plasmaB = exp(-abs(distB) * (20.0 / density));
    return vec3<f32>(plasmaR, plasmaG, plasmaB);
}

// --- MAIN LOOP ---
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);

    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) {
        return;
    }

    var uv = (fragCoord * 2.0 - dims) / min(dims.x, dims.y);

    // Parameters mapped from zoom_params
    let symmetryOrder = u.zoom_params.x;
    let plasmaDensity = u.zoom_params.y;
    let cymaticFreq = u.zoom_params.z;
    let swirlChaos = u.zoom_params.w;

    // Time & Audio
    let t = u.config.x * 0.5;
    let audio = u.config.y * 0.05;

    // Mouse coords
    let mX = (u.zoom_config.y / dims.x) * 2.0 - 1.0;
    let mY = -(u.zoom_config.z / dims.y) * 2.0 + 1.0;
    let mouse = vec2<f32>(mX, mY);

    // Mouse Swirl Interference
    let mDist = length(uv - mouse);
    let swirlStrength = exp(-mDist * 2.0) * swirlChaos;
    let swirlAngle = swirlStrength * sin(t + mDist * 10.0);
    let s = sin(swirlAngle);
    let c = cos(swirlAngle);
    let rotMat = mat2x2<f32>(c, -s, s, c);
    uv = rotMat * uv;

    // Polar Fold (Cymatic Mandalas)
    let foldedUv = fold(uv, symmetryOrder);
    let radius = length(uv);
    let angle = atan2(uv.y, uv.x);
    let sector = 6.2831853 / symmetryOrder;
    let foldedAngle = angle - sector * floor((angle + sector * 0.5) / sector);

    // Cymatic wave modulations
    let wave = sin(radius * cymaticFreq - t * 2.0 + audio * 5.0) * cos(foldedAngle * symmetryOrder + t);

    // Combine geometry (overlapping polygons/circles)
    var d = sdPolygon(foldedUv, 6.0) - 0.4 - wave * 0.1;
    d = min(d, sdCircle(foldedUv - vec2<f32>(0.5, 0.0), 0.2 - wave * 0.05));

    // Audio-driven folding
    d += sin(d * 10.0 - t * 3.0 + audio * 10.0) * 0.02;

    // Plasma bleed with Chromatic Aberration & Neon Palette
    let colorBase = getPalette(radius * 0.5 - t * 0.2 + audio);

    // Chromatic offsets for edge distortion
    let distR = d - 0.01 * plasmaDensity;
    let distG = d;
    let distB = d + 0.01 * plasmaDensity;

    let aberration = applyChromaticAberration(distR, distG, distB, plasmaDensity);
    var col = colorBase * aberration;

    // Intensify core
    col += vec3<f32>(1.0, 0.8, 0.9) * exp(-length(uv) * 5.0) * (0.5 + audio * 0.5);

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
