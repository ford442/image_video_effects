// ----------------------------------------------------------------
// Symbiotic Cyber-Fungal Core-Reactor
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn cellular(p: vec3<f32>) -> f32 {
    let pFloor = floor(p);
    let pFract = fract(p);
    var minDist = 1.0;

    for (var k = -1; k <= 1; k++) {
        for (var j = -1; j <= 1; j++) {
            for (var i = -1; i <= 1; i++) {
                let cell = vec3<f32>(f32(i), f32(j), f32(k));
                let h = hash33(pFloor + cell);
                let diff = cell + h - pFract;
                let dist = length(diff);
                minDist = min(minDist, dist);
            }
        }
    }
    return minDist;
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var pos = p;
    for(var i = 0; i < 4; i++) {
        f += cellular(pos) * amp;
        pos *= 2.0;
        amp *= 0.5;
    }
    return f;
}

fn map(p: vec3<f32>, time: f32) -> f32 {
    let core_density = u.zoom_params.x;
    let mycelium_spread = u.zoom_params.y;
    let quantum_noise = u.zoom_params.z;
    let mutation_rate = u.zoom_config.w;

    var pos = p;
    let mouse = (u.zoom_config.yz - 0.5) * 5.0;

    // Core singularity (mouse interactive)
    let core_pos = vec3<f32>(mouse.x, -mouse.y, 0.0);
    let d_core = length(pos - core_pos) - 0.5 * core_density;

    // Gyroid structure for mycelium
    pos *= 1.5;
    var d_gyroid = dot(sin(pos), cos(pos.zxy)) - 0.1;

    // Quantum noise modification
    let noise = fbm(pos * 2.0 + time * mutation_rate) * quantum_noise;
    d_gyroid += noise;

    // Attraction to core
    let dist_to_core = length(p - core_pos);
    let pull = smoothstep(2.0, 0.0, dist_to_core);
    d_gyroid -= pull * 0.5;

    // Blend core and mycelium
    let d_mycelium = d_gyroid * 0.5 / (1.0 + mycelium_spread);

    return min(d_core, d_mycelium);
}

fn getNormal(p: vec3<f32>, time: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time) - map(p - e.xyy, time),
        map(p + e.yxy, time) - map(p - e.yxy, time),
        map(p + e.yyx, time) - map(p - e.yyx, time)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimensions = vec2<f32>(u.config.zw);
    let coord = vec2<f32>(f32(global_id.x), f32(global_id.y));
    if (coord.x >= dimensions.x || coord.y >= dimensions.y) {
        return;
    }

    let uv = (coord - 0.5 * dimensions) / min(dimensions.x, dimensions.y);
    let time = u.config.x * u.zoom_params.w;
    let audio = u.config.y; // Audio-reactive spore emission

    var ro = vec3<f32>(0.0, 0.0, -4.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Slight camera rotation
    let rotMatrix = rot(time * 0.1);
    ro = vec3<f32>(rotMatrix * ro.xz, ro.y).xzy;
    rd = vec3<f32>(rotMatrix * rd.xz, rd.y).xzy;

    var t = 0.0;
    var col = vec3<f32>(0.0);
    var glow = 0.0;

    let mouse = (u.zoom_config.yz - 0.5) * 5.0;
    let core_pos = vec3<f32>(mouse.x, -mouse.y, 0.0);

    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p, time);

        // Volumetric glow accumulation
        glow += 0.01 / (0.01 + abs(d));

        if (d < 0.001 || t > 10.0) {
            if (d < 0.001) {
                let n = getNormal(p, time);
                let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
                let diff = max(dot(n, l), 0.0);

                // Color mapping
                let dist_to_core = length(p - core_pos);
                let mycelium_color = mix(vec3<f32>(0.1, 0.8, 0.9), vec3<f32>(0.8, 0.1, 0.6), clamp(p.z * 0.5 + 0.5, 0.0, 1.0));
                let deep_crevice = vec3<f32>(0.2, 0.0, 0.4);

                var base_col = mix(deep_crevice, mycelium_color, diff);

                // Audio reactive pulse
                base_col += vec3<f32>(0.1, 1.0, 0.5) * audio * 0.1 * cellular(p * 5.0);

                // Negative color space near singularity
                if (dist_to_core < u.zoom_params.x * 0.55) {
                    base_col = 1.0 - base_col;
                    base_col *= vec3<f32>(1.0, 0.5, 0.2); // Chromatic aberration effect
                }

                col = base_col;
            }
            break;
        }
        t += d;
    }

    // Apply glow
    col += vec3<f32>(0.05, 0.4, 0.5) * glow * 0.05;

    // Subsurface scattering approximation (cheap distance based fog)
    col = mix(col, vec3<f32>(0.0, 0.05, 0.1), 1.0 - exp(-0.1 * t));

    // Output
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
}
