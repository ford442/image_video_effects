// ═══════════════════════════════════════════════════════════════════
//  Chromatic Singularity-Loom
//  Category: generative
//  Features: raymarched, mouse-driven, audio-reactive, upgraded-rgba,
//            temporal-accretion, chromatic-lensing, audio-thread-chaos, bass-mass-pulse
//  Complexity: High
//  Upgraded: 2026-05-31
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
    ripples: array<vec4<f32>, 50>
};
fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(controlled, color.a);
}


const MAX_STEPS: i32 = 120;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.005;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn map(p: vec3<f32>, time: f32, audio_intensity: f32, params: vec4<f32>, mousePos: vec2<f32>, bass: f32) -> vec2<f32> {
    var pos = p;

    let center = vec3<f32>((mousePos.x - 0.5) * 10.0, (mousePos.y - 0.5) * -10.0, 0.0);
    let dist_sq = dot(pos - center, pos - center);

    var mass = params.x;
    if (mass == 0.0) { mass = 2.0; }
    // Bass-driven mass pulse
    mass = mass * (1.0 + bass * 0.5);

    if (dist_sq > 0.0) {
        pos += normalize(pos) * (mass / dist_sq);
    }

    var iterations_f = params.y;
    if (iterations_f == 0.0) { iterations_f = 4.0; }
    let iterations = i32(iterations_f);

    // Audio-reactive thread chaos
    let chaos = 0.5 + audio_intensity * 0.3 + bass * 0.2;
    for (var i = 0; i < iterations; i++) {
        pos = abs(pos) - vec3<f32>(0.5 + audio_intensity * 0.2);
        let r = rot(time * 0.2 * chaos + f32(i));
        let x_new = r[0][0]*pos.x + r[0][1]*pos.y;
        let y_new = r[1][0]*pos.x + r[1][1]*pos.y;
        pos.x = x_new;
        pos.y = y_new;
    }

    let d1 = length(pos.xz) - 0.05;
    let d2 = length(p - center) - 1.0;

    return vec2<f32>(min(d1, d2), 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let coords = vec2<i32>(id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(coords.x) >= res.x || f32(coords.y) >= res.y) { return; }

    let uv = (vec2<f32>(coords) - 0.5 * res) / res.y;
    let time = u.config.x;
    let audio_intensity = u.config.y;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    var mousePos = u.zoom_config.yz;
    if (mousePos.x == 0.0 && mousePos.y == 0.0) {
        mousePos = vec2<f32>(0.5);
    }

    let params = u.zoom_params;

    var ro = vec3<f32>(0.0, 0.0, -3.0);
    var rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    var dO = 0.0;
    var hit = false;
    for (var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * dO;
        let dS = map(p, time, audio_intensity, params, mousePos, bass);
        dO += dS.x;
        if (dS.x < SURF_DIST) {
            hit = true;
            break;
        }
        if (dO > MAX_DIST) {
            break;
        }
    }

    var col = vec3<f32>(0.0);
    if (hit) {
        let hit_p = ro + rd * dO;
        let center = vec3<f32>((mousePos.x - 0.5) * 10.0, (mousePos.y - 0.5) * -10.0, 0.0);
        let dist_center = length(hit_p - center);
        let plasma_index = min(u32(abs(dist_center) * 10.0 + time * 10.0), 255u);
        let plasma_color = plasmaBuffer[plasma_index].rgb;

        var chromatic_shift = params.w;
        if (chromatic_shift == 0.0) { chromatic_shift = 0.5; }

        // Chromatic gravitational lensing: R/B bend differently
        let phaseR = hit_p.z * chromatic_shift * (1.0 + bass * 0.1) + time;
        let phaseB = hit_p.z * chromatic_shift * (1.0 - treble * 0.1) + time;
        let c_shiftR = vec3<f32>(0.5) + vec3<f32>(0.5) * cos(vec3<f32>(phaseR, phaseR + 2.09, phaseR + 4.18));
        let c_shiftB = vec3<f32>(0.5) + vec3<f32>(0.5) * cos(vec3<f32>(phaseB, phaseB + 2.09, phaseB + 4.18));
        let c_shift = mix(c_shiftR, c_shiftB, 0.5);

        var accretion_glow = params.z;
        if (accretion_glow == 0.0) { accretion_glow = 1.0; }
        let bloom = accretion_glow * exp(-dist_center * 2.0) * (1.0 + audio_intensity * 2.0);

        col = plasma_color * c_shift * (1.0 / (1.0 + dO * dO * 0.1)) + plasma_color * bloom;

        // Temporal accretion disk memory
        let prev = textureSampleLevel(dataTextureC, u_sampler, vec2<f32>(coords) / res, 0.0).rgb;
        let diskMemory = mix(col, prev * 0.92, 0.06 + bass * 0.02);
        col = mix(col, diskMemory, 0.4);
    }

    let alpha = clamp(length(col) * 0.8 + bass * 0.05, 0.0, 1.0);
    textureStore(writeTexture, vec2<i32>(id.xy), applyGenerativePrimaryControls(vec4<f32>(col, alpha)));
    textureStore(dataTextureA, vec2<i32>(id.xy), vec4<f32>(col, alpha));
    let depthOut = clamp(dO / MAX_DIST, 0.0, 1.0);
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
