// Thick-liquid displacement with advected jets, vortices, and click pressure fronts.

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
    let viscosity = mix(0.08, 0.88, u.zoom_params.x);
    let dragStrength = mix(0.1, 2.0, u.zoom_params.y);
    let recovery = mix(0.88, 0.994, u.zoom_params.z);
    let scale = mix(0.01, 0.2, u.zoom_params.w);

    // Advect the RG offset state along a smooth moving liquid jet.
    let jetDirection = normalize(vec2<f32>(cos(time * 0.77), sin(time * 0.61)));
    let advectPixels = vec2<i32>(round(jetDirection * (1.0 + (1.0 - viscosity) * 3.0)));
    let baseCoord = coord - advectPixels;
    let previous = historyLoad(baseCoord);
    let upState = historyLoad(baseCoord + vec2<i32>(0, -1));
    let downState = historyLoad(baseCoord + vec2<i32>(0, 1));
    let leftState = historyLoad(baseCoord + vec2<i32>(-1, 0));
    let rightState = historyLoad(baseCoord + vec2<i32>(1, 0));
    let neighborState = (upState + downState + leftState + rightState) * 0.25;
    let diffusedOffset = mix(previous.xy, neighborState.xy, viscosity);

    let aspect = resolution.x / resolution.y;
    let delta = vec2<f32>((uv.x - u.zoom_config.y) * aspect, uv.y - u.zoom_config.z);
    let distanceToMouse = max(length(delta), 0.001);
    let radial = delta / distanceToMouse;
    let tangent = vec2<f32>(-radial.y, radial.x);
    let mouseMask = smoothstep(0.18, 0.0, distanceToMouse);
    let held = clamp(u.zoom_config.w, 0.0, 1.0);
    let mouseForce = (radial + tangent * sin(time * 5.0) * 0.55) * mouseMask * (0.12 + held * 1.88) * dragStrength * 0.018;

    // Traveling vortices form a second fast-motion family independent of input history.
    let vortexPhase = dot(uv, vec2<f32>(19.0, -13.0)) - time * (6.0 + dragStrength * 2.0);
    let vortexPacket = pow(0.5 + 0.5 * cos(vortexPhase), 16.0);
    let vortexForce = vec2<f32>(-jetDirection.y, jetDirection.x) * vortexPacket * dragStrength * (0.002 + audio.y * 0.004);
    var clickForce = vec2<f32>(0.0);
    var clickPressure = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age < 0.0 || age > 2.8) { continue; }
        {
            let rippleDelta = vec2<f32>((uv.x - ripple.x) * aspect, uv.y - ripple.y);
            let rippleDistance = max(length(rippleDelta), 0.001);
            let ring = abs(rippleDistance - age * (0.18 + audio.x * 0.08));
            let front = (1.0 - smoothstep(0.0, 0.026, ring)) * (1.0 - age / 2.8);
            clickForce += rippleDelta / rippleDistance * front * 0.018 * dragStrength;
            clickPressure += front;
        }
    }
    var newOffset = (diffusedOffset * recovery) + mouseForce + vortexForce + clickForce;
    newOffset = clamp(newOffset, vec2<f32>(-0.5), vec2<f32>(0.5));
    let strain = length(newOffset - previous.xy);
    let pressureDrive = mouseMask * (0.08 + held * 0.52) + clickPressure * 0.22 + vortexPacket * audio.x * 0.08;
    let thickness = clamp(mix(previous.z, neighborState.z, viscosity * 0.28) * recovery + pressureDrive, 0.0, 2.0);
    let dragEnergy = clamp(mix(previous.w, neighborState.w, 0.2) * recovery + strain * 3.0 + clickPressure * 0.12, 0.0, 2.0);
    textureStore(dataTextureA, coord, vec4<f32>(newOffset, thickness, dragEnergy));

    let sampleUV = clamp(uv - newOffset * scale, vec2<f32>(0.0), vec2<f32>(1.0));
    let color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    let normal = normalize(vec3<f32>(newOffset, 0.02));
    let lightDirection = normalize(vec3<f32>(0.5, 0.5, 1.0));
    let specular = pow(max(dot(normal, lightDirection), 0.0), 20.0) * (length(newOffset) + thickness * 0.16) * (1.0 + audio.z);
    let ridgeColor = vec3<f32>(0.14 + audio.x * 0.12, 0.38 + audio.y * 0.28, 0.62 + audio.z * 0.38) * dragEnergy * 0.22;
    let hdr = color.rgb + vec3<f32>(specular) + ridgeColor;
    let mapped = clamp((hdr * (2.51 * hdr + 0.03)) / (hdr * (2.43 * hdr + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
    let alpha = clamp(color.a * 0.78 + thickness * 0.12 + dragEnergy * 0.08 + length(newOffset) * 0.3, 0.0, 1.0);
    let finalColor = vec4<f32>(mapped, alpha);
    textureStore(writeTexture, coord, finalColor);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
