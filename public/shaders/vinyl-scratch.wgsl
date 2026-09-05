// Vinyl Scratch — Composer batch cyber/digital/glitch cohort 3
// Groove cinema with spring stylus, held drag warp, click scratch bursts,
// exact C groove-sparkle coherence, ACES + semantic alpha.

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + vec2<f32>(1.0, 0.0)));
}

// Temporal film grain
fn temporalGrain(gid: vec2<f32>, time: f32, treble: f32) -> f32 {
    let t1 = hash21(gid + fract(time * 0.7) * 100.0);
    let t2 = hash21(gid * 1.3 + fract(time * 0.3) * 100.0);
    return (mix(t1, t2, 0.5) - 0.5) * (1.0 + treble * 0.3);
}

// Vinyl dust particles: animated on surface
fn vinylDust(uv: vec2<f32>, time: f32, dist: f32, dustAmount: f32) -> f32 {
    let dustUV1 = uv * 8.0 + time * 0.2;
    let dustUV2 = uv * 12.0 - time * 0.15;
    let dust1 = hash21(floor(dustUV1));
    let dust2 = hash21(floor(dustUV2));
    let dust = mix(dust1, dust2, 0.5);
    // Dust is more visible on outer grooves
    let grooveFactor = smoothstep(0.1, 0.5, dist);
    return step(1.0 - dustAmount * 0.3, dust) * grooveFactor * 0.4;
}

// Groove lighting: reflections along concentric grooves
fn grooveReflection(uv: vec2<f32>, dist: f32, time: f32, angle: f32, bass: f32) -> vec3<f32> {
    let grooveFreq = 80.0;
    let groovePhase = dist * grooveFreq - time * 2.0;
    let groove = sin(groovePhase) * 0.5 + 0.5;
    let grooveSharp = pow(groove, 4.0);
    
    // Light source angle
    let lightAngle = time * 0.5 + bass * 0.3;
    let angleDiff = abs(angle - lightAngle);
    let lightWrap = exp(-angleDiff * angleDiff * 2.0) + exp(-(angleDiff - 6.283) * (angleDiff - 6.283) * 2.0);
    
    let reflection = grooveSharp * lightWrap * 0.3 * (1.0 + bass * 0.5);
    return vec3<f32>(reflection * 1.0, reflection * 0.95, reflection * 0.85);
}

// Analog warmth: color temperature shift toward orange/yellow
fn analogWarmth(color: vec3<f32>, amount: f32) -> vec3<f32> {
    let warmth = vec3<f32>(1.06, 1.02, 0.94);
    return mix(color, color * warmth, amount);
}

// Saturation roll-off: colors desaturate toward white in highlights
fn saturationRolloff(color: vec3<f32>, amount: f32) -> vec3<f32> {
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let highlight = smoothstep(0.5, 1.0, luma);
    return mix(color, vec3<f32>(luma), highlight * amount);
}

// Vignette
fn vignette(uv: vec2<f32>, strength: f32) -> f32 {
    let center = uv - vec2<f32>(0.5);
    let r = length(center) * 1.4142;
    return pow(1.0 - r * strength, 2.0);
}

// Radial chromatic aberration
fn radialChromatic(uv: vec2<f32>, center: vec2<f32>, strength: f32) -> vec2<f32> {
    let dir = uv - center;
    let r2 = dot(dir, dir);
    return dir * r2 * strength;
}

// Lens dirt: subtle dust overlay on bright areas
fn lensDirt(uv: vec2<f32>, time: f32, brightness: f32) -> f32 {
    let dirt1 = hash21(uv * 3.0 + time * 0.01);
    let dirt2 = hash21(uv * 7.0 - time * 0.015);
    let dirt = mix(dirt1, dirt2, 0.5);
    return smoothstep(0.6, 0.9, dirt) * brightness * 0.12;
}

// Groove sparkle: tiny bright points on groove ridges
fn grooveSparkle(uv: vec2<f32>, dist: f32, time: f32, treble: f32) -> f32 {
    let sparkleUV = floor(uv * vec2<f32>(200.0, 200.0)) / 200.0;
    let sparkleHash = hash21(sparkleUV + time * 0.5);
    let sparkle = step(1.0 - treble * 0.1, sparkleHash);
    let grooveMask = sin(dist * 300.0) * 0.5 + 0.5;
    return sparkle * grooveMask * 0.3 * treble;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let bass   = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids   = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let held = u.zoom_config.w > 0.5;
    let aspect = resolution.x / resolution.y;

    var smoothMouse = mousePos;
    let hasSpring = arrayLength(&extraBuffer) > 138u;
    if (hasSpring && extraBuffer[138] > 0.5) {
        smoothMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    }
    if (global_id.x == 0u && global_id.y == 0u && hasSpring) {
        var springPos = smoothMouse;
        var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        if (extraBuffer[138] <= 0.5) {
            springPos = mousePos;
            springVel = vec2<f32>(0.0);
        } else {
            let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
            let omega = 10.0;
            let accel = (mousePos - springPos) * (omega * omega) - springVel * (2.0 * omega);
            springVel += accel * dt;
            springPos += springVel * dt;
        }
        extraBuffer[133] = springPos.x;
        extraBuffer[134] = springPos.y;
        extraBuffer[135] = springVel.x;
        extraBuffer[136] = springVel.y;
        extraBuffer[137] = time;
        extraBuffer[138] = 1.0;
        smoothMouse = springPos;
    }

    let depth = textureLoad(readDepthTexture, coord, 0).r;
    let depthGroove = mix(0.7, 1.3, depth);

    let rotationSpeed = (u.zoom_params.x - 0.5) * 4.0 * (1.0 + bass * 0.5);
    let scratchAmount = u.zoom_params.y;
    let wobble = u.zoom_params.z * (1.0 + mids * 0.7);
    let noiseIntensity = u.zoom_params.w * (1.0 + treble * 0.6);

    // Cinematic params
    let caStrength = 0.015 + bass * 0.02;
    let vignetteStrength = 0.5 + bass * 0.15;
    let warmthAmount = 0.2 + mids * 0.1;
    let saturationRoll = 0.25 + treble * 0.15;
    let dustAmount = 0.3 + treble * 0.2;
    let grooveLightAmount = 0.4 + bass * 0.3;

    let center = vec2<f32>(0.5, 0.5);
    let dir = uv - center;
    let dirCorrected = vec2<f32>(dir.x * aspect, dir.y);
    let dist = length(dirCorrected);
    let angle = atan2(dirCorrected.y, dirCorrected.x);

    var rot = time * rotationSpeed;
    let scratchOffset = (smoothMouse.x - 0.5) * 10.0 * scratchAmount;
    rot = rot + scratchOffset;
    if (held) { rot += sin(time * 18.0) * 0.08 * scratchAmount; }

    var clickPop = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 1.2) {
            let radius = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
            clickPop = max(clickPop, exp(-age * 3.0) * (1.0 - smoothstep(0.0, 0.08, radius)));
        }
    }
    rot += clickPop * 0.5;

    let wobbleOffset = sin(angle * 2.0 + time * 5.0) * 0.02 * wobble * dist * depthGroove;

    let cosA = cos(rot);
    let sinA = sin(rot);
    let rotatedDirX = dirCorrected.x * cosA - dirCorrected.y * sinA;
    let rotatedDirY = dirCorrected.x * sinA + dirCorrected.y * cosA;

    let sampleUV = vec2<f32>(rotatedDirX / aspect, rotatedDirY) + center + vec2<f32>(wobbleOffset, wobbleOffset);

    // Chromatic wobble + radial chromatic aberration
    let caOffset = radialChromatic(uv, center, caStrength);
    let wobbleR = sin(angle * 2.5 + time * 6.0) * 0.003 * wobble * (1.0 + bass);
    let wobbleB = sin(angle * 1.5 + time * 4.0) * 0.003 * wobble * (1.0 + treble);
    let rUV = clamp(sampleUV + vec2<f32>(wobbleR, 0.0) + caOffset, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(sampleUV - vec2<f32>(wobbleB, 0.0) - caOffset, vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    var color = vec4<f32>(r, g, b, textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).a);

    let grooveNoise = fract(sin(dot(uv * time, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    let grooveIntensity = (sin(dist * 400.0) * 0.5 + 0.5) * noiseIntensity * depthGroove;

    color = mix(color, vec4<f32>(grooveNoise, grooveNoise, grooveNoise, color.a), grooveIntensity * 0.2);

    // ── Vinyl dust particles ──
    let dust = vinylDust(uv, time, dist, dustAmount);
    let dustColor = vec3<f32>(0.85, 0.8, 0.75) * dust;
    color = vec4<f32>(color.rgb + dustColor, color.a);

    // ── Groove lighting / reflections ──
    let reflection = grooveReflection(uv, dist, time, angle, bass) * grooveLightAmount;
    color = vec4<f32>(color.rgb + reflection, color.a);

    // ── Groove sparkle ──
    let sparkle = grooveSparkle(uv, dist, time, treble);
    let prevSparkle = textureLoad(dataTextureC, coord, 0).a;
    let sparkleCoherent = mix(sparkle, prevSparkle * 0.9, 0.35);
    color = vec4<f32>(color.rgb + vec3<f32>(sparkleCoherent + clickPop * 0.25), color.a);

    // ── Temporal film grain ──
    let grain = temporalGrain(vec2<f32>(global_id.xy), time, treble);
    color = vec4<f32>(color.rgb + grain * 0.06, color.a);

    // ── Vignette ──
    let vig = vignette(uv, vignetteStrength * 0.7);
    color = vec4<f32>(color.rgb * mix(0.5, 1.0, vig), color.a);

    // ── Analog warmth ──
    color = vec4<f32>(analogWarmth(color.rgb, warmthAmount), color.a);

    // ── Saturation roll-off in highlights ──
    color = vec4<f32>(saturationRolloff(color.rgb, saturationRoll), color.a);

    // ── Lens dirt on bright areas ──
    let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let brightMask = smoothstep(0.5, 0.9, luma);
    let dirt = lensDirt(uv, time, brightMask);
    color = vec4<f32>(color.rgb + vec3<f32>(0.9, 0.85, 0.7) * dirt, color.a);

    color.a = clamp(color.a + grooveIntensity * 0.15 + clickPop * 0.2 + bass * 0.05, 0.0, 1.0);

    var finalColor = acesToneMap(clamp(color.rgb, vec3<f32>(0.0), vec3<f32>(1.5)) * (0.95 + bass * 0.05));
    textureStore(writeTexture, coord, vec4<f32>(finalColor, color.a));
    textureStore(dataTextureA, coord, vec4<f32>(finalColor, color.a));

    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}