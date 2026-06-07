// ═══════════════════════════════════════════════════════════════════
//  Luma Flow Field
//  Category: simulation
//  Features: gradient-flow, audio-reactive, depth-aware, temporal, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-23
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530717958647692;

fn getLuma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f*f*(3.0-2.0*f);
    return mix(mix(hash2(i), hash2(i+vec2<f32>(1,0)), u.x),
               mix(hash2(i+vec2<f32>(0,1)), hash2(i+vec2<f32>(1,1)), u.x), u.y);
}

fn curlNoise(p: vec2<f32>, octaves: i32) -> vec2<f32> {
    var curl = vec2<f32>(0.0);
    var amp = 1.0; var freq = 1.0; var pp = p;
    for (var i = 0; i < octaves; i++) {
        let e = 0.002 / freq;
        let nx = vnoise(pp + vec2<f32>(0.0, e)) - vnoise(pp - vec2<f32>(0.0, e));
        let ny = vnoise(pp + vec2<f32>(e, 0.0)) - vnoise(pp - vec2<f32>(e, 0.0));
        curl += amp * normalize(vec2<f32>(nx, -ny) + vec2<f32>(0.0001));
        pp = pp * 2.1 + vec2<f32>(1.7, 9.2);
        freq *= 2.0; amp *= 0.5;
    }
    return curl / f32(octaves);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let resolution = vec2<f32>(u.config.z, u.config.w);
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(coord) / resolution;
    let time = u.config.x;
    let e = 1.0 / resolution;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let flowScale     = u.zoom_params.x * 5.0 + 1.0;
    let trailDecay    = 0.93 + u.zoom_params.y * 0.065;
    let curlStrength  = u.zoom_params.z * (1.0 + mids * 0.3);
    let audioSens     = u.zoom_params.w;

    let l00 = getLuma(textureSampleLevel(readTexture, u_sampler, uv+vec2<f32>(-e.x,-e.y),0.0).rgb);
    let l10 = getLuma(textureSampleLevel(readTexture, u_sampler, uv+vec2<f32>( 0.0,-e.y),0.0).rgb);
    let l20 = getLuma(textureSampleLevel(readTexture, u_sampler, uv+vec2<f32>( e.x,-e.y),0.0).rgb);
    let l01 = getLuma(textureSampleLevel(readTexture, u_sampler, uv+vec2<f32>(-e.x, 0.0),0.0).rgb);
    let l21 = getLuma(textureSampleLevel(readTexture, u_sampler, uv+vec2<f32>( e.x, 0.0),0.0).rgb);
    let l02 = getLuma(textureSampleLevel(readTexture, u_sampler, uv+vec2<f32>(-e.x, e.y),0.0).rgb);
    let l12 = getLuma(textureSampleLevel(readTexture, u_sampler, uv+vec2<f32>( 0.0, e.y),0.0).rgb);
    let l22 = getLuma(textureSampleLevel(readTexture, u_sampler, uv+vec2<f32>( e.x, e.y),0.0).rgb);

    let gx = (l20+2.0*l21+l22)-(l00+2.0*l01+l02);
    let gy = (l02+2.0*l12+l22)-(l00+2.0*l10+l20);
    let grad    = vec2<f32>(gx, gy);
    let gradMag = length(grad);

    let lumaFlow = vec2<f32>(-gy, gx);
    let curlUV  = uv * flowScale + vec2<f32>(time * 0.04, time * 0.03);
    let curlVec = curlNoise(curlUV, 3);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthVortex = depth * 0.6;

    let totalFlow = lumaFlow * (0.06 + bass * audioSens * 0.04)
                  + curlVec  * curlStrength * (0.025 + depthVortex * 0.02 + treble * audioSens * 0.015);

    let sampleUV = clamp(uv + totalFlow, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

    let angle  = atan2(grad.y + curlVec.y * curlStrength, grad.x + curlVec.x * curlStrength);
    let palShift = u.zoom_params.x * 0.1 + time * 0.02;
    let palIdx = u32(clamp(fract(angle/TAU + 0.5 + palShift) * 255.0, 0.0, 255.0));
    let bufLen = arrayLength(&plasmaBuffer);
    let palette = plasmaBuffer[palIdx % max(1u, bufLen)].rgb;
    let iridBlend = curlStrength * 0.7 * smoothstep(0.0, 0.25, gradMag);
    color = mix(color, color * (0.5 + palette * 0.9), iridBlend);

    let history = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let decay   = trailDecay * (1.0 - bass * audioSens * 0.04);
    color = mix(color, history * decay, 0.5 + curlStrength * 0.1);
    color *= decay;

    let luma  = getLuma(color);
    let bloom = max(0.0, luma - 0.7) * 3.0;
    let alpha = clamp(luma*0.4 + bloom*0.5 + gradMag*1.5 + depth*0.15 + bass*0.1, 0.0, 1.0);

    let finalColor = vec4<f32>(color, alpha);

    textureStore(writeTexture, coord, finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
