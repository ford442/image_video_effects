// Stylized liquid-metal mirror with advected capillary packets and click impacts.

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

fn historyLoad(pixel: vec2<i32>) -> vec4<f32> {
    let size = vec2<i32>(textureDimensions(dataTextureC));
    return textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), size - vec2<i32>(1)), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;
    let viscosity = u.zoom_params.x;
    let reflectAmount = u.zoom_params.y;
    let impactAmount = u.zoom_params.z;
    let metallic = u.zoom_params.w;

    // Directional state advection gives the mirror a coherent liquid shear.
    let shear = vec2<f32>(cos(time * 0.67), sin(time * 0.53));
    let advect = vec2<i32>(round(shear * (1.0 + (1.0 - viscosity) * 2.0)));
    let baseCoord = coord - advect;
    let prev = historyLoad(baseCoord);
    let left = historyLoad(baseCoord + vec2<i32>(-1, 0));
    let right = historyLoad(baseCoord + vec2<i32>(1, 0));
    let top = historyLoad(baseCoord + vec2<i32>(0, -1));
    let bottom = historyLoad(baseCoord + vec2<i32>(0, 1));
    let lap = (left.x + right.x + top.x + bottom.x) * 0.25 - prev.x;

    let aspect = resolution.x / resolution.y;
    let mouseDist = length((uv - u.zoom_config.yz) * vec2<f32>(aspect, 1.0));
    let mouseImpact = smoothstep(0.24, 0.0, mouseDist) * impactAmount * (0.25 + u.zoom_config.w * 1.5);
    let packetPhase = dot(uv, normalize(vec2<f32>(0.78, 0.62))) * 34.0 - time * (8.0 + (1.0 - viscosity) * 9.0);
    let capillaryPacket = sin(packetPhase) * exp(-pow((fract(packetPhase / 6.28318) - 0.5) / 0.14, 2.0)) * (0.025 + audio.z * 0.06);
    let rainTrack = pow(0.5 + 0.5 * sin(uv.x * 119.0 + sin(uv.y * 17.0) - time * 7.0), 22.0) * audio.z * 0.035;

    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 3.0) {
            let ring = abs(length((uv - ripple.xy) * vec2<f32>(aspect, 1.0)) - age * (0.20 + audio.x * 0.08));
            clickFront += sin(ring * 180.0) * (1.0 - smoothstep(0.0, 0.035, ring)) * (1.0 - age / 3.0);
        }
    }

    let damping = mix(0.985, 0.90, viscosity);
    var wave = vec3<f32>(0.0);
    wave.x = clamp((prev.x + lap * 0.88 + mouseImpact * 0.20 + capillaryPacket + rainTrack + clickFront * impactAmount * 0.12) * damping, -1.0, 1.0);
    wave.y = mix(prev.y, (right.x - left.x) * 0.5, 0.38);
    wave.z = mix(prev.z, (bottom.x - top.x) * 0.5, 0.38);
    let waveNormal = vec2<f32>(wave.y, wave.z) * (0.03 + reflectAmount * 0.07);
    let reflectUV = clamp(uv + waveNormal, vec2<f32>(0.0), vec2<f32>(1.0));
    let input = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let reflectedA = textureSampleLevel(readTexture, u_sampler, reflectUV, 0.0).rgb;
    let reflectedB = textureSampleLevel(readTexture, u_sampler, clamp(reflectUV + waveNormal * 0.6, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let reflected = (reflectedA + reflectedB) * 0.5;
    let metalTint = mix(vec3<f32>(0.65, 0.68, 0.72), vec3<f32>(0.84, 0.87, 0.92), metallic);
    var color = mix(input.rgb, reflected * metalTint, 0.25 + reflectAmount * 0.65);
    let specular = pow(clamp(0.5 + wave.x * 0.8 - length(wave.yz), 0.0, 1.0), 5.0) * (0.3 + audio.x * 0.7);
    color = clamp(color + vec3<f32>(0.95, 0.98, 1.0) * specular * reflectAmount, vec3<f32>(0.0), vec3<f32>(1.0));
    let waveEnergy = abs(wave.x) + length(wave.yz) * 0.5;
    let semanticAlpha = clamp(0.65 + waveEnergy * 1.6 + reflectAmount * 0.25, 0.5, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(color, semanticAlpha));
    textureStore(dataTextureA, coord, vec4<f32>(wave.x, wave.y, wave.z, semanticAlpha * 0.8));
    let generatedDepth = clamp(0.3 + waveEnergy * 0.4, 0.0, 0.95);
    textureStore(writeDepthTexture, coord, vec4<f32>(generatedDepth, 0.0, 0.0, 0.0));
}
