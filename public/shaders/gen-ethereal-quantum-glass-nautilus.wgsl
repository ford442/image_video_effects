// ----------------------------------------------------------------
// Ethereal Quantum-Glass Nautilus
// Category: generative
// ----------------------------------------------------------------
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Refraction Index, .y = Spiral Tightness, .z = Iridescence Shift, .w = Audio Reactivity
  ripples: array<vec4<f32>, 50>,
};

const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 20.0;
const SURF_DIST: f32 = 0.005;

// Rotate 2D
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Voronoi noise for micro-fractures
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453);
}

fn voronoi(p: vec3<f32>) -> f32 {
    let n = floor(p);
    let f = fract(p);
    var md = 8.0;
    for (var i = -1; i <= 1; i++) {
        for (var j = -1; j <= 1; j++) {
            for (var k = -1; k <= 1; k++) {
                let g = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash3(n + g);
                let d = g + o - f;
                let dist = dot(d, d);
                if (dist < md) {
                    md = dist;
                }
            }
        }
    }
    return md;
}

// Nautilus Logarithmic Spiral SDF
fn map(p_in: vec3<f32>, audioReactive: f32, spiralTightness: f32) -> f32 {
    var p = p_in;

    // Audio pulsing
    let pulse = 1.0 + audioReactive * 0.2 * sin(u.config.x * 2.0);
    p *= 1.0 / pulse;

    // Logarithmic spiral transformation
    let a = atan2(p.z, p.x);
    let r = length(p.xz);

    // Core parameters for nautilus
    let b = spiralTightness; // Tightness
    let theta = log(r) / b;

    // Chamber spacing and rounding
    var n = theta - a / 6.2831853;
    let nf = floor(n);
    let nf1 = nf + 1.0;

    let r0 = exp((nf + a / 6.2831853) * b);
    let r1 = exp((nf1 + a / 6.2831853) * b);

    let d0 = length(vec2<f32>(r - r0, p.y)) - r0 * 0.4;
    let d1 = length(vec2<f32>(r - r1, p.y)) - r1 * 0.4;

    var d = min(d0, d1);

    // Quantum Micro-fractures
    let vNoise = voronoi(p * 20.0);
    d += vNoise * 0.02;

    return d * pulse; // Scale back distance
}

// Raymarching
fn raymarch(ro: vec3<f32>, rd: vec3<f32>, audioReactive: f32, spiralTightness: f32) -> f32 {
    var d0 = 0.0;
    for (var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * d0;
        let dS = map(p, audioReactive, spiralTightness);
        d0 += dS;
        if (d0 > MAX_DIST || abs(dS) < SURF_DIST) {
            break;
        }
    }
    return d0;
}

// Calculate Normal
fn calcNormal(p: vec3<f32>, audioReactive: f32, spiralTightness: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p, audioReactive, spiralTightness);
    let n = d - vec3<f32>(
        map(p - e.xyy, audioReactive, spiralTightness),
        map(p - e.yxy, audioReactive, spiralTightness),
        map(p - e.yyx, audioReactive, spiralTightness)
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }

    // Setup UVs
    let base_uv = vec2<f32>(f32(id.x), f32(id.y)) / resolution.xy;
    var uv = base_uv * 2.0 - 1.0;
    uv.x *= resolution.x / resolution.y;

    // Parameters
    let refrIndex = u.zoom_params.x; // Refraction Index
    let spiralTightness = u.zoom_params.y; // Spiral Tightness
    let iridescenceShift = u.zoom_params.z; // Iridescence Shift
    let audioParam = u.zoom_params.w; // Audio Reactivity

    // Audio Reactivity from Data Texture C
    let audioSample = textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(0.5, 0.5), 0.0).r;
    let audioReactive = audioParam * audioSample;

    // Camera
    let ta = vec3<f32>(0.0, 0.0, 0.0);
    var ro = vec3<f32>(0.0, 2.0, -4.0);

    // Gravity well mouse interaction
    var mouse_uv = u.zoom_config.yz * 2.0 - 1.0;
    mouse_uv.x *= resolution.x / resolution.y;

    // Rotate camera around origin over time
    let time = u.config.x * 0.2;
    ro = vec3<f32>(ro.x * cos(time) - ro.z * sin(time), ro.y, ro.x * sin(time) + ro.z * cos(time));

    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = cross(cu, cw);

    var rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    // Apply Gravity Well bending to ray direction based on mouse
    if (u.zoom_config.w > 0.0) {
        let mouseDist = length(uv - mouse_uv);
        let pull = 0.5 / (mouseDist * mouseDist + 0.1);
        rd = normalize(rd + vec3<f32>(uv - mouse_uv, 0.0) * pull * 0.2);
    }

    // Raymarching
    let d = raymarch(ro, rd, audioReactive, spiralTightness);

    var col = vec3<f32>(0.02, 0.02, 0.05); // Background Void

    if (d < MAX_DIST) {
        let p = ro + rd * d;
        let n = calcNormal(p, audioReactive, spiralTightness);

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -2.0));
        let diffuse = max(dot(n, lightDir), 0.0);

        // Iridescence / Thin-film interference
        let viewDir = normalize(ro - p);
        let NdotV = max(dot(n, viewDir), 0.0);
        let phase = NdotV * 5.0 + iridescenceShift * 6.28 + time;
        let iridescence = 0.5 + 0.5 * cos(vec3<f32>(1.0, 1.2, 1.4) * phase);

        // Refraction (approximated)
        let refl = reflect(rd, n);
        let envRefr = textureSampleLevel(readTexture, non_filtering_sampler, base_uv + n.xy * 0.1 * (refrIndex - 1.0), 0.0).rgb;

        // Subsurface scattering (glowing core)
        let coreDist = length(p);
        let glow = exp(-coreDist * 0.5) * vec3<f32>(0.2, 0.8, 1.0) * (1.0 + audioReactive);

        col = iridescence * diffuse * 0.5 + envRefr * 0.3 + glow;

        // Spectral dispersion (chromatic aberration) on edges
        let edge = 1.0 - NdotV;
        col += vec3<f32>(edge * 0.5, edge * 0.2, 0.0);
    }

    // Accumulate with read texture for persistence/trails (optional)
    let oldCol = textureSampleLevel(readTexture, non_filtering_sampler, base_uv, 0.0).rgb;
    col = mix(col, oldCol, 0.8);

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
