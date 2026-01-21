struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 30>,
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
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

fn hash12(p: vec2<f32>) -> f32 {
    var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i + vec2<f32>(0.0, 0.0)),
                   hash12(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash12(i + vec2<f32>(0.0, 1.0)),
                   hash12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    var pos = p;
    // Rotation matrix
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    for (var i = 0; i < 5; i++) {
        v += a * noise(pos);
        pos = rot * pos * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(coord) + 0.5) / vec2<f32>(dims);

    // Uniforms
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let aspect = f32(dims.x) / f32(dims.y);

    // Adjust UV for aspect ratio for distance calcs
    let p = uv;
    let m = mouse;
    let p_aspect = vec2<f32>(p.x * aspect, p.y);
    let m_aspect = vec2<f32>(m.x * aspect, m.y);

    let dist = length(p_aspect - m_aspect);
    let angle = atan2(p_aspect.y - m_aspect.y, p_aspect.x - m_aspect.x);

    // Sample original image
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let luma = dot(baseColor, vec3<f32>(0.299, 0.587, 0.114));

    // Flux Core Effect
    // 1. Central Glow
    let glow = 0.05 / (dist + 0.001);

    // 2. Electrical Arcs
    // Use angle and distance to create lightning bolts emanating from center
    // Perturb angle with noise based on distance and time
    let angle_noise = fbm(vec2<f32>(dist * 5.0 - time * 2.0, angle * 2.0));
    let bolt_path = abs(sin(angle * 10.0 + angle_noise * 5.0));

    // Sharpen the bolt
    let bolt = smoothstep(0.95, 0.98, bolt_path);

    // Fade bolts with distance, but allow them to connect to bright spots
    // If luma is high, the bolt can travel further or be brighter
    let conductivity = luma * 2.0;
    let attenuation = smoothstep(0.5 + conductivity * 0.5, 0.0, dist);

    // Bolt Color
    let fluxColor = vec3<f32>(0.4, 0.8, 1.0); // Cyan
    let hotColor = vec3<f32>(1.0, 1.0, 1.0); // White core

    var finalBolt = mix(fluxColor, hotColor, bolt) * bolt * attenuation * 5.0;

    // 3. Distortion Shockwave
    // Distort the background image based on the bolt intensity
    let distort = bolt * 0.02 * (1.0 / (dist + 0.1));
    let distortedUV = uv + vec2<f32>(cos(angle), sin(angle)) * distort;

    let distortedColor = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0).rgb;

    // 4. Combine
    // Add bolts to distorted image
    // Mouse hover adds extra energy
    let energy = 1.0 + sin(time * 10.0) * 0.2;

    var finalColor = distortedColor + finalBolt * energy;

    // Add central core
    finalColor += hotColor * smoothstep(0.05, 0.0, dist) * 2.0;
    finalColor += fluxColor * glow * 0.5;

    textureStore(writeTexture, coord, vec4<f32>(finalColor, 1.0));
}
