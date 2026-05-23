// ═══════════════════════════════════════════════════════════════════
//  Fluid Lens Dynamics
//  Category: image
//  Features: mouse-driven, audio-reactive, depth-aware, spring-mass,
//            velocity-sensitive, splash-response, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-10
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

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
    let len = length(v);
    return select(vec2<f32>(0.0, 1.0), v / len, len > 0.0001);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let coords = vec2<i32>(global_id.xy);
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / max(resolution.y, 1.0);

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let surfaceTension = u.zoom_params.x;
    let viscosity = u.zoom_params.y;
    let mass = u.zoom_params.z;
    let splashThreshold = mix(0.2, 4.0, u.zoom_params.w);

    let rippleCount = min(u32(u.config.y), 50u);

    let rc = min(rippleCount, 50u);
    let has_one = rc > 1u;
    let idx_latest = select(0u, max(rc, 1u) - 1u, has_one);
    let idx_prev   = select(0u, max(rc, 2u) - 2u, has_one);
    let latest = u.ripples[idx_latest];
    let prev = u.ripples[idx_prev];
    let dt1 = max(latest.z - prev.z, 0.016);
    var velocity = select(vec2<f32>(0.0), (latest.xy - prev.xy) / dt1, has_one);
    var impulseAge = select(0.0, max(time - latest.z, 0.0), has_one);

    let has_two = rc > 2u;
    let idx_older = select(0u, max(rc, 3u) - 3u, has_two);
    let older = u.ripples[idx_older];
    let dt2 = max(prev.z - older.z, 0.016);
    let prevVelocity = select(vec2<f32>(0.0), (prev.xy - older.xy) / dt2, has_two);
    let dt_blend = max(dt1, dt2);
    var acceleration = select(vec2<f32>(0.0), (velocity - prevVelocity) / dt_blend, has_two);

    let velocityAspect = velocity * vec2<f32>(aspect, 1.0);
    let speed = length(velocityAspect);
    let accelMag = length(acceleration * vec2<f32>(aspect, 1.0));
    let velDir = safeNormalize(velocityAspect);
    let perpDir = vec2<f32>(-velDir.y, velDir.x);

    let baseRadius = mix(0.14, 0.42, 0.55 + surfaceTension * 0.35 - mass * 0.15) * (1.0 + bass * 0.18);
    let stretch = 1.0 + speed * mix(0.02, 0.10, 1.0 - viscosity) / max(mix(0.5, 2.0, mass), 0.05);
    let rel = uv - mouse;
    let relAspect = vec2<f32>(rel.x * aspect, rel.y);
    let parallel = dot(relAspect, velDir) / max(stretch, 0.2);
    let orthogonal = dot(relAspect, perpDir) * mix(1.0, 1.25, viscosity);
    let radial = length(vec2<f32>(parallel, orthogonal));

    let naturalFreq = mix(2.5, 10.0, surfaceTension) / mix(0.6, 2.4, mass);
    let damping = mix(0.25, 3.0, viscosity);
    let springPulse = exp(-impulseAge * damping) * sin(impulseAge * naturalFreq * 6.2831853);
    let splashTrigger = smoothstep(splashThreshold, splashThreshold * 2.5, accelMag);
    let splashWave = sin(radial * (28.0 + surfaceTension * 20.0) - impulseAge * (8.0 + naturalFreq * 2.0)) *
        exp(-impulseAge * (1.5 + damping)) * splashTrigger;

    let lensProfile = smoothstep(baseRadius, 0.0, radial);
    let distortionWeight = lensProfile * (0.35 + surfaceTension * 0.75) * (1.0 + springPulse * 0.35);
    let radialDir = safeNormalize(relAspect);

    var sampleAspect = relAspect * (1.0 - distortionWeight * 0.65);
    sampleAspect = sampleAspect + radialDir * splashWave * 0.012 * splashTrigger;
    sampleAspect = sampleAspect + velDir * springPulse * 0.01 * speed;
    let sampleUV = mouse + vec2<f32>(sampleAspect.x / aspect, sampleAspect.y);

    let color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;

    let rim = smoothstep(baseRadius, baseRadius * 0.65, radial) * (1.0 - lensProfile);
    let rimGlow = vec3<f32>(0.05, 0.07, 0.10) * rim * (0.5 + abs(springPulse));
    let finalRgb = color.rgb + rimGlow + vec3<f32>(treble * 0.02, mids * 0.015, bass * 0.01);
    let finalAlpha = clamp(color.a * mix(1.0, 0.92 + rim * 0.08, lensProfile) * mix(0.94, 1.02, depth), 0.0, 1.0);

    let finalColor = vec4<f32>(finalRgb, finalAlpha);

    textureStore(writeTexture, coords, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, global_id.xy, finalColor);
}
