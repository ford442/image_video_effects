// ═══════════════════════════════════════════════════════════════════
//  Topological Phase Weave
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal
//  Complexity: High
//  Created: 2026-05-31
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

// ═══ Hash / Noise ═══
fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    let p3 = fract(vec3<f32>(p.x, p.y, p.x) * vec3<f32>(0.1031, 0.1030, 0.0973));
    let p4 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

// ═══ Director Field (nematic angle) ═══
// Computes the local nematic director angle at position p given defect configuration
fn directorField(p: vec2<f32>, time: f32, defectDensity: f32, mobility: f32) -> f32 {
    var angle = 0.0;
    let numDefects = 8;

    for (var i: i32 = 0; i < numDefects; i++) {
        let fi = f32(i);
        // Defect positions orbit and wander
        let phase = fi * 0.7853 + time * mobility * (0.3 + fi * 0.1);
        let radius = 0.3 + 0.2 * sin(time * 0.1 * (fi + 1.0));
        let defectPos = vec2<f32>(
            cos(phase) * radius + sin(time * 0.07 * (fi + 2.0)) * 0.15,
            sin(phase) * radius + cos(time * 0.09 * (fi + 1.5)) * 0.15
        ) * defectDensity;

        // Topological charge: alternate +1/2 and -1/2 defects
        let charge = select(-0.5, 0.5, i % 2 == 0);

        let dp = p - defectPos;
        let defectAngle = atan2(dp.y, dp.x);
        angle += charge * defectAngle;
    }

    // Add smooth background field from noise
    angle += noise(p * 2.0 + time * 0.05) * 0.5;

    return angle;
}

// ═══ Defect proximity (singularity detector) ═══
fn defectProximity(p: vec2<f32>, time: f32, defectDensity: f32, mobility: f32) -> vec2<f32> {
    var minDist = 100.0;
    var charge = 0.0;
    let numDefects = 8;

    for (var i: i32 = 0; i < numDefects; i++) {
        let fi = f32(i);
        let phase = fi * 0.7853 + time * mobility * (0.3 + fi * 0.1);
        let radius = 0.3 + 0.2 * sin(time * 0.1 * (fi + 1.0));
        let defectPos = vec2<f32>(
            cos(phase) * radius + sin(time * 0.07 * (fi + 2.0)) * 0.15,
            sin(phase) * radius + cos(time * 0.09 * (fi + 1.5)) * 0.15
        ) * defectDensity;

        let dist = length(p - defectPos);
        if (dist < minDist) {
            minDist = dist;
            charge = select(-0.5, 0.5, i % 2 == 0);
        }
    }

    return vec2<f32>(minDist, charge);
}

// ═══ Iridescent color mapping (oil-slick) ═══
fn iridescent(angle: f32, proximity: f32, time: f32) -> vec3<f32> {
    let t = angle * 0.3183 + time * 0.05; // normalize angle to [0,1]-ish range
    let film = proximity * 6.0 + t;

    // Thin-film interference colors
    let r = 0.5 + 0.5 * cos(6.2832 * (film + 0.0));
    let g = 0.5 + 0.5 * cos(6.2832 * (film + 0.33));
    let b = 0.5 + 0.5 * cos(6.2832 * (film + 0.67));

    return vec3<f32>(r, g, b);
}

// ═══ Smooth bass envelope ═══
fn bassEnv(prev: f32, current: f32, attack: f32, release: f32) -> f32 {
    if (current > prev) {
        return mix(prev, current, attack);
    }
    return mix(prev, current, release);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x;

    // Audio input
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Parameters
    let defectDensity = mix(0.5, 2.0, u.zoom_params.x);     // Bass increases density
    let mobility = mix(0.2, 1.5, u.zoom_params.y);           // Mids control mobility
    let perturbation = mix(0.0, 1.0, u.zoom_params.z);       // Treble perturbation
    let colorSaturation = mix(0.3, 1.5, u.zoom_params.w);

    // Mouse: pin defect or create attractor
    let mousePos = u.zoom_config.yz;

    // Smooth audio
    var prevBass = extraBuffer[0];
    let smoothBass = bassEnv(prevBass, bass, 0.15, 0.02);
    extraBuffer[0] = smoothBass;

    // Aspect ratio
    let aspect = res.x / res.y;
    let p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;

    // Audio-modulated parameters
    let dynDensity = defectDensity * (1.0 + smoothBass * 0.5);
    let dynMobility = mobility * (1.0 + mids * 0.4);
    let dynPerturb = perturbation + treble * 0.3;

    // Mouse influence: create local attractor field
    let mp = (mousePos - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
    let mouseDist = length(p - mp);
    let mouseAttract = exp(-mouseDist * 4.0) * 0.8;

    // ═══ DIRECTOR FIELD COMPUTATION ═══
    let angle = directorField(p, time, dynDensity, dynMobility);

    // Add high-frequency treble perturbation
    let perturbAngle = angle + noise(p * 10.0 + time * 2.0) * dynPerturb * 0.5;

    // Mouse pins the local field
    let finalAngle = mix(perturbAngle, atan2(p.y - mp.y, p.x - mp.x), mouseAttract);

    // ═══ FIELD VISUALIZATION ═══
    // Director vector
    let director = vec2<f32>(cos(finalAngle), sin(finalAngle));

    // Line-integral convolution style: streak pattern along director
    let licScale = 8.0 + dynPerturb * 4.0;
    let streak = noise(p * licScale + director * 2.0 + time * 0.1);
    let streak2 = noise(p * licScale * 0.5 - director * 1.5 + time * 0.07);
    let fieldVis = streak * 0.6 + streak2 * 0.4;

    // ═══ DEFECT VISUALIZATION ═══
    let defect = defectProximity(p, time, dynDensity, dynMobility);
    let defectDist = defect.x;
    let defectCharge = defect.y;

    // Singularity glow
    let singularityGlow = exp(-defectDist * 15.0) * 1.5;

    // Defect type coloring: +1/2 warm (comet), -1/2 cool (trefoil)
    let positiveCol = vec3<f32>(1.0, 0.6, 0.2); // warm amber
    let negativeCol = vec3<f32>(0.2, 0.5, 1.0); // cool blue
    let defectCol = mix(negativeCol, positiveCol, step(0.0, defectCharge)) * singularityGlow;

    // ═══ COLOR MAPPING ═══
    // Iridescent base from director angle
    let iridescentBase = iridescent(finalAngle, defectDist, time);

    // Brush-stroke pattern from field
    let brushIntensity = smoothstep(0.3, 0.7, fieldVis);

    // Compose final color
    var col = iridescentBase * brushIntensity * colorSaturation;

    // Add defect singularity highlights
    col += defectCol;

    // Nematic order parameter visualization: darker near defect cores
    let orderParam = smoothstep(0.0, 0.15, defectDist);
    col *= orderParam * 0.8 + 0.2;

    // Background: very dark with subtle field texture
    let bgField = fieldVis * 0.08;
    col = max(col, vec3<f32>(bgField));

    // Audio pulse on defect regions
    col += defectCol * smoothBass * 0.4;

    // Temporal feedback for trail persistence
    let prev = textureLoad(dataTextureC, coord, 0).rgb;
    col = mix(col, max(col, prev * 0.88), 0.3);

    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.5;
    col *= vignette;

    // Alpha based on field visibility and defect proximity
    let alpha = clamp(brushIntensity * 0.8 + singularityGlow * 0.5, 0.0, 1.0);

    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(1.0 - orderParam, 0.0, 0.0, 0.0));
}
