// ----------------------------------------------------------------
// Luminescent Quantum-Silicate Diatom
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
  zoom_params: vec4<f32>,  // .x = Pore Density, .y = Pulse Speed, .z = Iridescence Spread, .w = Bioluminescence Shift
  ripples: array<vec4<f32>, 50>,
};

fn rot(a: f32) -> mat2x2<f32> {
  let s = sin(a);
  let c = cos(a);
  return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p: vec3<f32>) -> vec3<f32> {
  let p2 = vec3<f32>(
    dot(p, vec3<f32>(127.1, 311.7, 74.7)),
    dot(p, vec3<f32>(269.5, 183.3, 246.1)),
    dot(p, vec3<f32>(113.5, 271.9, 124.6))
  );
  return -1.0 + 2.0 * fract(sin(p2) * 43758.5453123);
}

fn simplex3d(p: vec3<f32>) -> f32 {
  let K1 = 0.333333333;
  let K2 = 0.166666667;
  let i = floor(p + vec3<f32>((p.x + p.y + p.z) * K1));
  let d0 = p - (i - vec3<f32>((i.x + i.y + i.z) * K2));

  var e = vec3<f32>(step(d0.yzx, d0.xyz));
  let j1 = e * (vec3<f32>(1.0) - e.zxy);
  let j2 = vec3<f32>(1.0) - e.zxy * (vec3<f32>(1.0) - e);

  let d1 = d0 - (j1 - vec3<f32>(K2));
  let d2 = d0 - (j2 - vec3<f32>(K2 * 2.0));
  let d3 = d0 - (vec3<f32>(1.0 - K2 * 3.0));

  var w = max(vec4<f32>(0.6) - vec4<f32>(dot(d0, d0), dot(d1, d1), dot(d2, d2), dot(d3, d3)), vec4<f32>(0.0));
  w = w * w;
  w = w * w;

  let d = vec4<f32>(
    dot(d0, hash33(i)),
    dot(d1, hash33(i + j1)),
    dot(d2, hash33(i + j2)),
    dot(d3, hash33(i + vec3<f32>(1.0)))
  );

  return dot(w, d) * 31.316;
}

fn map(p: vec3<f32>, mouse_pos: vec3<f32>) -> vec2<f32> {
    var pos = p;

    // Mouse Interaction: micro-cellular gravity well
    let dist_to_mouse = length(pos - mouse_pos);
    let strength = 0.5 * u.zoom_config.w; // active on click/drag
    pos += normalize(pos - mouse_pos) * (strength / (dist_to_mouse + 0.1));

    // Domain folding for lattice
    let spacing = vec3<f32>(4.0);
    pos = pos - spacing * round(pos / spacing);

    // Base shape: Octahedron
    var s = abs(pos.x) + abs(pos.y) + abs(pos.z) - 1.5;

    // High-frequency noise for pores (Pore Density mapped to u.zoom_params.x)
    let pore_density = u.zoom_params.x * 5.0 + 1.0;
    let pores = simplex3d(pos * pore_density) * 0.3;
    s += pores;

    return vec2<f32>(s * 0.5, 1.0); // ID 1.0 for shell
}

fn get_normal(p: vec3<f32>, mouse_pos: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, mouse_pos).x - map(p - e.xyy, mouse_pos).x,
        map(p + e.yxy, mouse_pos).x - map(p - e.yxy, mouse_pos).x,
        map(p + e.yyx, mouse_pos).x - map(p - e.yyx, mouse_pos).x
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) {
        return;
    }
    let uv = vec2<f32>(f32(global_id.x), f32(global_id.y)) / resolution;
    let cuv = (uv - 0.5) * vec2<f32>(resolution.x / resolution.y, 1.0) * 2.0;

    let time = u.config.x * u.zoom_params.y; // Pulse Speed mapped to u.zoom_params.y

    // Audio reactivity
    let audio_val = textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(uv.x, 0.5), 0.0).r;

    let mouse_uv = u.zoom_config.yz;
    let cmouse = (mouse_uv - 0.5) * vec2<f32>(resolution.x / resolution.y, 1.0) * 2.0;
    let mouse_pos = vec3<f32>(cmouse * 5.0, 0.0);

    var ro = vec3<f32>(0.0, 0.0, -5.0 + time * 0.5);
    var rd = normalize(vec3<f32>(cuv, 1.5));

    // Camera rotation
    ro = vec3<f32>(rot(time * 0.2) * ro.xy, ro.z);
    rd = vec3<f32>(rot(time * 0.2) * rd.xy, rd.z);

    var t = 0.0;
    var d = 0.0;
    var col = vec3<f32>(0.0);

    var vol_acc = 0.0;

    for(var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p, mouse_pos);
        d = res.x;

        // Volumetric accumulation for cytoplasm
        if (d > 0.0) {
           let cyto_noise = simplex3d(p * 2.0 - vec3<f32>(0.0, 0.0, time * 2.0)) * 0.5 + 0.5;
           let emissive = smoothstep(0.4, 0.6, cyto_noise) * 0.02 * (1.0 + audio_val * 2.0);
           vol_acc += emissive;
        }

        if (d < 0.01) {
            let n = get_normal(p, mouse_pos);
            let v = -rd;

            // Fresnel for iridescence
            let f = pow(1.0 - max(dot(n, v), 0.0), 3.0);

            // Chromatic aberration gradient based on iridescence spread
            let spread = u.zoom_params.z;
            let iridescent_col = vec3<f32>(
                sin(f * 10.0 * spread),
                sin(f * 12.0 * spread + 2.0),
                sin(f * 14.0 * spread + 4.0)
            ) * 0.5 + 0.5;

            // Bioluminescence shift
            let shift = u.zoom_params.w;
            let bio_col = vec3<f32>(0.0, 1.0 - shift, shift + 0.2) * 2.0;

            col += (iridescent_col * 0.5 + bio_col * audio_val) * (1.0 - f);

            // Inner cytoplasm emission added
            col += bio_col * vol_acc;
            break;
        }

        t += d;
        if (t > 20.0) {
            col += vec3<f32>(0.0, 0.1, 0.2) * vol_acc * u.zoom_params.w;
            break;
        }
    }

    col = mix(col, vec3<f32>(0.0, 0.0, 0.05), smoothstep(10.0, 20.0, t));

    // Soft bloom post-processing approximation
    col += col * 0.2 * audio_val;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
}
