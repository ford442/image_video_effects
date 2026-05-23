// ═══════════════════════════════════════════════════════════════════════════════
//  Neon Pulse — Planck Blackbody Radiation Grid
//  Category: lighting-effects
//  Features: audio-reactive, depth-aware, procedural
//  Complexity: Medium-High
//  Scientific: Planck spectrum, colour temperature 1000K–18000K per cell,
//              incandescent to blue-white arc lamp range, audio-driven heating
//  Upgraded: Phase B — from simple sine grid to blackbody radiation
// ═══════════════════════════════════════════════════════════════════════════════

@group(0) @binding(0)  var u_sampler: sampler;
@group(0) @binding(1)  var readTexture: texture_2d<f32>;
@group(0) @binding(2)  var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3)  var<uniform> u: Uniforms;
@group(0) @binding(4)  var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5)  var non_filtering_sampler: sampler;
@group(0) @binding(6)  var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7)  var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8)  var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9)  var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config:      vec4<f32>,  // x=Time, y=ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
    zoom_params: vec4<f32>,  // x=GridDensity, y=BaseTemp, z=AudioHeat, w=GlowWidth
    ripples:     array<vec4<f32>, 50>,
}

// Planck blackbody colour (1000K–20000K) → approximate linear RGB
fn blackbody(T: f32) -> vec3<f32> {
    let t = clamp(T, 1000.0, 20000.0);
    var r: f32; var g: f32; var b: f32;
    if (t <= 6600.0) {
        r = 1.0;
        g = clamp((99.47 * log(t / 100.0) - 161.12) / 255.0, 0.0, 1.0);
        b = select(0.0, clamp((138.52 * log(t / 100.0 - 10.0) - 305.04) / 255.0, 0.0, 1.0), t > 2000.0);
    } else {
        let lt = t / 100.0 - 60.0;
        r = clamp(329.70 * pow(lt, -0.1332) / 255.0, 0.0, 1.0);
        g = clamp(288.12 * pow(lt, -0.0755) / 255.0, 0.0, 1.0);
        b = 1.0;
    }
    return vec3<f32>(r, g, b);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var q = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return fract(sin(q) * 43758.5453);
}

fn hash11(p: f32) -> f32 {
    return fract(sin(p * 127.1 + 311.7) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv      = vec2<f32>(global_id.xy) / resolution;
    let time    = u.config.x;
    let bass    = plasmaBuffer[0].x;
    let mids    = plasmaBuffer[0].y;
    let treble  = plasmaBuffer[0].z;

    let gridN     = mix(4.0, 20.0, u.zoom_params.x);
    let baseT     = mix(800.0, 12000.0, u.zoom_params.y);   // Kelvin
    let audioHeat = mix(0.0, 8000.0, u.zoom_params.z);
    let glowW     = mix(0.02, 0.45, u.zoom_params.w);

    let aspect = resolution.x / resolution.y;
    let gridUV = vec2<f32>(uv.x * aspect, uv.y) * gridN;
    let cell   = floor(gridUV);
    let frac   = fract(gridUV);

    // Each cell has a unique base temperature & oscillation phase
    let h    = hash22(cell);
    let h1   = hash11(cell.x * 13.7 + cell.y * 7.3);

    // Temperature oscillates with audio and time
    let osc  = 0.5 + 0.5 * sin(time * (1.0 + h.x * 3.0) + h.y * 6.28318);
    let audioBoost = bass * audioHeat + mids * audioHeat * 0.3 + treble * audioHeat * 0.15;
    let T    = baseT + h1 * 4000.0 + osc * 2500.0 + audioBoost;

    // Distance from cell centre: multiple emission shapes
    let centre = vec2<f32>(0.5);
    let d      = length(frac - centre);

    // Secondary: Voronoi-style nearest feature for texture
    let d2 = length(frac - (centre + (h - 0.5) * 0.3));

    // Gaussian hotspot brightness (depends on temperature)
    let sigmaGlow = glowW * (T / 8000.0); // hotter = wider glow
    let spot      = exp(-d * d / (sigmaGlow * sigmaGlow));

    // Halo: faint outer glow at lower temperature
    let haloT  = T * 0.5;
    let halo   = exp(-d2 * d2 / (sigmaGlow * sigmaGlow * 4.0)) * 0.3;

    // Blackbody colour for hotspot and halo
    let bbHot  = blackbody(T);
    let bbHalo = blackbody(haloT);

    // Combine
    var emitted = bbHot * spot + bbHalo * halo;

    // Flicker: Poisson-style random intensity variation
    let flicker = 0.85 + 0.15 * sin(time * (5.0 + h.x * 20.0) + h.y * 100.0);
    emitted *= flicker;

    // Plasma arc: thin bright lines connecting neighbouring cells (high treble)
    let arcUV  = frac - 0.5;
    let arcLine = exp(-abs(arcUV.y) * 25.0 / max(treble * 0.5 + 0.1, 0.1));
    let arcGlow = arcLine * treble * 0.4;
    emitted += blackbody(18000.0) * arcGlow * h.x;

    // Read background for compositing with depth
    let bg    = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Objects in foreground cast shadows (near depth blocks light)
    let shadowMask = mix(0.3, 1.0, depth);
    emitted *= shadowMask;

    // Add glow onto background
    let luma     = dot(emitted, vec3<f32>(0.2126, 0.7152, 0.0722));
    let finalRGB = bg + emitted;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, luma));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(T / 20000.0, spot, luma, osc));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(luma, 0.0, 0.0, 0.0));
}

