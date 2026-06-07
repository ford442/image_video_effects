// ----------------------------------------------------------------
// Neon-Plasma Biomechanical Hive
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Shatter Threshold, y=Chime Density, z=Refraction Index, w=Transmission
    ripples: array<vec4<f32>, 50>,
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


fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + 33.33);
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn voronoi(x: vec3<f32>) -> vec2<f32> {
    let p = floor(x);
    var f = fract(x);
    var res = vec2<f32>(8.0, 8.0);
    for (var k = -1; k <= 1; k++) {
        for (var j = -1; j <= 1; j++) {
            for (var i = -1; i <= 1; i++) {
                let b = vec3<f32>(f32(i), f32(j), f32(k));
                let r = vec3<f32>(b) - f + hash3(p + b);
                let d = dot(r, r);
                if (d < res.x) {
                    res.y = res.x;
                    res.x = d;
                } else if (d < res.y) {
                    res.y = d;
                }
            }
        }
    }
    return vec2<f32>(sqrt(res.x), sqrt(res.y));
}

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn fbm(p: vec3<f32>) -> f32 {
    var value = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    var pos = p;
    for (var i = 0; i < 4; i++) {
        let v = voronoi(pos * freq);
        value += amp * v.x;
        pos = pos * 2.0;
        amp *= 0.5;
    }
    return value;
}

fn map(pos: vec3<f32>, mouse_pos: vec3<f32>, mouse_pull: f32) -> vec2<f32> {
    var p = pos;

    let pull_dist = length(p - mouse_pos);
    if (pull_dist > 0.1) {
        let pull_force = mouse_pull / (pull_dist * pull_dist);
        p -= normalize(mouse_pos - p) * clamp(pull_force, 0.0, 2.0);
    }

    let v = voronoi(p * 2.0);
    let displacement = (v.y - v.x) * 0.3;

    let q = fract(p * 0.5) - 0.5;
    let sphere = length(q) - 0.25 + displacement;

    let cyl_x = length(q.yz) - 0.1;
    let cyl_y = length(q.xz) - 0.1;
    let cyl_z = length(q.xy) - 0.1;
    let cyl = min(min(cyl_x, cyl_y), cyl_z);

    let d = smin(sphere, cyl, 0.2);

    return vec2<f32>(d, 1.0); // ID 1.0 for hive
}

fn map_spores(p: vec3<f32>, time: f32) -> f32 {
    let cell = floor(p);
    let h = hash3(cell);
    let offset = vec3<f32>(sin(time * 0.5 + h.x * 6.28), cos(time * 0.4 + h.y * 6.28), sin(time * 0.3 + h.z * 6.28)) * 0.3;
    let q = fract(p) - 0.5 - offset;
    return length(q) - 0.05;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

    let uv = (vec2<f32>(global_id.xy) * 2.0 - res) / min(res.x, res.y);
    let time = u.config.x;

    // Parameters
    let breathing_speed = u.zoom_config.x;
    let neon_intensity = u.zoom_config.y;
    let spore_density = u.zoom_config.z;
    let magnetic_pull = u.zoom_config.w;

    let audio = u.config.y * 2.0;

    var ro = vec3<f32>(time * 0.5, 0.0, time * 0.2);
    let rd = normalize(vec3<f32>(uv, 1.0));

    let mouse_pos = ro + vec3<f32>(u.zoom_params.x * 5.0, u.zoom_params.y * 5.0, 5.0);

    // Chromatic Aberration loop
    var col = vec3<f32>(0.0);
    let ca_offsets = array<vec3<f32>, 3>(
        vec3<f32>(0.005, 0.0, 0.0),
        vec3<f32>(0.0, 0.005, 0.0),
        vec3<f32>(0.0, 0.0, 0.005)
    );

    for (var c = 0; c < 3; c++) {
        var t = 0.0;
        var p = ro;
        var glow = 0.0;
        let rd_offset = normalize(rd + ca_offsets[c]);

        for (var i = 0; i < 64; i++) {
            p = ro + rd_offset * t;
            let p_breathe = p * (1.0 + sin(time * breathing_speed) * 0.05);
            let d = map(p_breathe, mouse_pos, magnetic_pull).x;

            let spore_d = map_spores(p, time);
            glow += 0.05 / (0.01 + abs(spore_d)) * spore_density * (1.0 + audio * 0.5);

            if (d < 0.001) {
                break;
            }
            if (t > 20.0) {
                break;
            }
            t += min(d, spore_d) * 0.7;
        }

        if (t < 20.0) {
            let vein_noise = fbm(p * 5.0 - time);
            let vein_glow = pow(vein_noise, 3.0) * neon_intensity * (1.0 + audio);

            let eps = vec2<f32>(0.001, 0.0);
            let n = normalize(vec3<f32>(
                map(p + eps.xyy, mouse_pos, magnetic_pull).x - map(p - eps.xyy, mouse_pos, magnetic_pull).x,
                map(p + eps.yxy, mouse_pos, magnetic_pull).x - map(p - eps.yxy, mouse_pos, magnetic_pull).x,
                map(p + eps.yyx, mouse_pos, magnetic_pull).x - map(p - eps.yyx, mouse_pos, magnetic_pull).x
            ));

            let light_dir = normalize(vec3<f32>(1.0, 1.0, -1.0));
            let diff = max(dot(n, light_dir), 0.0);
            let base_color = vec3<f32>(0.1, 0.15, 0.2); // Gunmetal

            // Audio reactive neon colors
            let audio_color = plasmaBuffer[0].rgb;
            var neon_color = vec3<f32>(0.0, 1.0, 1.0); // Cyan
            neon_color = mix(neon_color, vec3<f32>(1.0, 0.0, 1.0), audio); // Shift to magenta
            if(length(audio_color) > 0.1) {
                 neon_color = mix(neon_color, audio_color, 0.5);
            }

            let c_val = base_color * diff + neon_color * vein_glow;
            if (c == 0) { col.r = c_val.r; }
            else if (c == 1) { col.g = c_val.g; }
            else { col.b = c_val.b; }
        }
        if (c == 0) { col.r += glow; }
        else if (c == 1) { col.g += glow; }
        else { col.b += glow; }
    }

    col = col / (1.0 + col); // Tone mapping

    textureStore(writeTexture, vec2<i32>(global_id.xy), applyGenerativePrimaryControls(vec4<f32>(col, 1.0)));
}
