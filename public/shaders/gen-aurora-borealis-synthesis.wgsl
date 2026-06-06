// ═══════════════════════════════════════════════════════════════════
//  Aurora Borealis Synthesis
//  Category: generative
//  Features: volumetric-raymarch, audio-reactive, mouse-ripples, upgraded-rgba,
//            chromatic-wavelength-split, temporal-aurora, audio-storm, depth-output
//  Complexity: High
//  Upgraded: 2026-05-31
// ═══════════════════════════════════════════════════════════════════

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

fn hash3(p: vec3<f32>) -> f32 {
    let p2 = fract(p * 0.3183099 + vec3<f32>(0.1, 0.1, 0.1));
    let q = p2 * 17.0;
    return fract(q.x * q.y * q.z * (q.x + q.y + q.z));
}

fn noise3(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f2 = f * f * (vec3<f32>(3.0) - vec2<f32>(2.0).xxx * f);
    let n = p.x + p.y * 57.0 + 113.0 * p.z;
    let res = mix(
        mix(
            mix(hash3(p), hash3(p + vec3<f32>(1.0, 0.0, 0.0)), f2.x),
            mix(hash3(p + vec3<f32>(0.0, 1.0, 0.0)), hash3(p + vec3<f32>(1.0, 1.0, 0.0)), f2.x),
            f2.y
        ),
        mix(
            mix(hash3(p + vec3<f32>(0.0, 0.0, 1.0)), hash3(p + vec3<f32>(1.0, 0.0, 1.0)), f2.x),
            mix(hash3(p + vec3<f32>(0.0, 1.0, 1.0)), hash3(p + vec3<f32>(1.0, 1.0, 1.0)), f2.x),
            f2.y
        ),
        f2.z
    );
    return res;
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var p2 = p;
    for (var i = 0u; i < 4u; i++) {
        f += amp * noise3(p2);
        p2 *= 2.0;
        amp *= 0.5;
    }
    return f;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = textureDimensions(readTexture);
    let uv = vec2<f32>(id.xy) / vec2<f32>(dims);

    if (id.x >= dims.x || id.y >= dims.y) {
        return;
    }

    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let base_color = textureLoad(readTexture, vec2<i32>(id.xy), 0);

    var accumulated_color = vec3<f32>(0.0);
    var accumulated_alpha = 0.0;

    let storm_dir = u.zoom_config.yz;
    let swirl_speed = max(0.1, u.zoom_params.y);
    let volume_height = max(0.5, u.zoom_params.x);
    let brightness_scale = max(0.1, u.zoom_params.z);

    let motion_offset = time * swirl_speed * 0.5 + vec3<f32>(storm_dir.x * time, bass * 2.0, storm_dir.y * time);

    let ray_dir = normalize(vec3<f32>(uv * 2.0 - 1.0, 1.0));
    let steps = 20;
    let step_size = volume_height / f32(steps);
    var p = vec3<f32>(uv * 10.0, 0.0) + motion_offset;

    for (var i = 0; i < steps; i++) {
        p += ray_dir * step_size;

        // Chromatic wavelength splitting: R and B sample at different heights
        let nR = fbm(p + vec3<f32>(0.0, treble * 0.8, 0.0));
        let nG = fbm(p + vec3<f32>(0.0, mids * 0.5, 0.0));
        let nB = fbm(p + vec3<f32>(0.0, bass * 0.3, 0.0));

        var intensityR = smoothstep(0.4, 0.8, nR);
        var intensityG = smoothstep(0.4, 0.8, nG);
        var intensityB = smoothstep(0.4, 0.8, nB);
        let fade = (1.0 - (f32(i) / f32(steps)));
        intensityR *= fade;
        intensityG *= fade;
        intensityB *= fade;

        if (intensityG > 0.0) {
            let color_index = u32(clamp(intensityG * 128.0, 0.0, 127.0));
            let mapped_color = plasmaBuffer[color_index].rgb;
            accumulated_color += vec3<f32>(mapped_color.r * intensityR, mapped_color.g * intensityG, mapped_color.b * intensityB) * brightness_scale * step_size * 10.0;
            accumulated_alpha += intensityG * 0.1;
        }

        if (accumulated_alpha >= 1.0) { break; }
    }

    // Temporal aurora persistence: previous frame blends for smoother curtains
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    accumulated_color = mix(accumulated_color, prev * 0.9, 0.08 + bass * 0.02);

    // Interactive mouse ripples affect aurora intensity and displacement
    var ripple_effect = 0.0;
    for (var i = 0u; i < 50u; i++) {
        let ripple = u.ripples[i];
        if (ripple.w > 0.0) {
            let dist = distance(uv, ripple.xy);
            ripple_effect += (1.0 - smoothstep(ripple.z - 0.05, ripple.z, dist)) * smoothstep(0.0, 0.05, dist) * ripple.w;
        }
    }

    accumulated_color += vec3<f32>(ripple_effect * 0.5);

    let final_color = base_color.rgb + accumulated_color;
    let alpha = clamp(accumulated_alpha + base_color.a * 0.5, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(id.xy), applyGenerativePrimaryControls(vec4<f32>(final_color, alpha)));
    textureStore(dataTextureA, vec2<i32>(id.xy), vec4<f32>(final_color, alpha));
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(clamp(accumulated_alpha, 0.0, 1.0), 0.0, 0.0, 0.0));
}
