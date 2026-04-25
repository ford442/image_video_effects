// ═══════════════════════════════════════════════════════════════════
//  Wave Equation RGBA Fluid
//  Category: advanced-hybrid
//  Features: mouse-driven, temporal, rgba-state-machine, physics
//  Complexity: Very High
//  Chunks From: wave-equation.wgsl (wave propagation),
//               alpha-fluid-simulation-paint.wgsl (Navier-Stokes)
//  Created: 2026-04-18
//  By: Agent CB-11
// ═══════════════════════════════════════════════════════════════════
//  Coupled wave equation and incompressible fluid simulation packed
//  into a single RGBA32FLOAT state texture.
//  R = wave height (signed, displacement from equilibrium)
//  G = wave velocity (signed, time derivative of height)
//  B = fluid pressure (signed, incompressibility field)
//  A = dye density (advected scalar, visualizes flow)
//  Wave velocity drives fluid motion; fluid pressure dampens waves.
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hsv2rgb (from alpha-fluid-simulation-paint.wgsl) ═══
fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let h = hsv.x * 6.0;
    let s = hsv.y;
    let v = hsv.z;
    let c = v * s;
    let x = c * (1.0 - abs(h - floor(h / 2.0) * 2.0 - 1.0));
    let m = v - c;
    var rgb: vec3<f32>;
    if (h < 1.0) { rgb = vec3(c, x, 0.0); }
    else if (h < 2.0) { rgb = vec3(x, c, 0.0); }
    else if (h < 3.0) { rgb = vec3(0.0, c, x); }
    else if (h < 4.0) { rgb = vec3(0.0, x, c); }
    else if (h < 5.0) { rgb = vec3(x, 0.0, c); }
    else { rgb = vec3(c, 0.0, x); }
    return rgb + vec3(m);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let ps = 1.0 / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let time = u.config.x;

    // Read previous state
    let prevState = textureLoad(dataTextureC, coord, 0);
    var height = prevState.r;
    var waveVel = prevState.g;
    var pressure = prevState.b;
    var dye = prevState.a;

    // Seed on first frame
    if (time < 0.1) {
        height = 0.0;
        waveVel = 0.0;
        pressure = 0.0;
        dye = 0.0;
        // Seed dye at center
        let centerDist = length(uv - vec2<f32>(0.5));
        if (centerDist < 0.1) {
            dye = 0.5 + 0.5 * sin(centerDist * 30.0);
        }
    }

    // Clamp
    height = clamp(height, -2.0, 2.0);
    waveVel = clamp(waveVel, -1.0, 1.0);
    pressure = clamp(pressure, -2.0, 2.0);
    dye = clamp(dye, 0.0, 5.0);

    // Parameters
    let waveSpeed = mix(0.1, 0.5, u.zoom_params.x);
    let damping = mix(0.96, 0.999, u.zoom_params.y);
    let viscosity = u.zoom_params.z * 0.001 + 0.0001;
    let sourceStrength = mix(0.1, 1.0, u.zoom_params.w);

    // === WAVE EQUATION LAPLACIAN (3x3) ===
    let left = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(-ps.x, 0.0), 0.0);
    let right = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(ps.x, 0.0), 0.0);
    let up = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0, -ps.y), 0.0);
    let down = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0, ps.y), 0.0);

    let laplacian = left.r + right.r + up.r + down.r - 4.0 * height;

    // Wave equation: acceleration = c^2 * laplacian
    let c2 = waveSpeed * waveSpeed;
    let acceleration = c2 * laplacian;

    // === FLUID COUPLING ===
    // Fluid velocity derived from wave gradient (waves push fluid)
    var fluidVel = vec2<f32>(right.r - left.r, down.r - up.r) * 0.5 * waveSpeed * 2.0;
    fluidVel = clamp(fluidVel, vec2<f32>(-0.5), vec2<f32>(0.5));

    // Advect dye with combined fluid+wave velocity
    let advectUV = clamp(uv - fluidVel * 0.016, vec2<f32>(0.0), vec2<f32>(1.0));
    let advected = textureSampleLevel(dataTextureC, u_sampler, advectUV, 0.0);
    dye = advected.a;

    // Fluid viscosity diffusion on dye
    dye += viscosity * (left.a + right.a + up.a + down.a - 4.0 * dye) * 100.0;

    // === PRESSURE PROJECTION (single Jacobi step) ===
    let pL = left.b;
    let pR = right.b;
    let pD = down.b;
    let pU = up.b;
    let divergence = ((pR - pL) / (2.0 * ps.x) + (pU - pD) / (2.0 * ps.y));
    pressure = (pL + pR + pD + pU - divergence * ps.x * ps.x * 4.0) * 0.25;
    pressure = clamp(pressure, -2.0, 2.0);

    // Pressure gradient affects wave velocity (fluid dampens waves)
    let pressureGrad = vec2<f32>((pR - pL) / (2.0 * ps.x), (pU - pD) / (2.0 * ps.y));
    waveVel -= pressureGrad.x * 0.1;

    // Update wave
    waveVel = waveVel + acceleration;
    waveVel = waveVel * damping;
    height = height + waveVel;

    // === MOUSE WAVE INJECTION ===
    let mousePos = u.zoom_config.yz;
    let mouseDistSq = dot(uv - mousePos, uv - mousePos);
    let mouseRadius = 0.02;
    if (mouseDistSq < mouseRadius * mouseRadius) {
        let wave = sin(time * 10.0) * sourceStrength * 0.5;
        height = height + wave * (1.0 - sqrt(mouseDistSq) / mouseRadius);
    }

    // Mouse injects dye
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.15, 0.0, mouseDist) * mouseDown;
    dye += mouseInfluence * 0.3;

    // === RIPPLE INJECTION ===
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 2.0 && rDist < 0.08) {
            let inject = smoothstep(0.08, 0.0, rDist) * max(0.0, 1.0 - age * 0.5);
            dye += inject * 0.5;
            let dir = normalize(uv - ripple.xy + vec2<f32>(0.0001));
            fluidVel += dir * inject * 0.1;
        }
    }

    // === BOUNDARY CONDITIONS ===
    let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    let edgeFade = smoothstep(0.0, 0.05, edgeDist);
    height = height * edgeFade;
    waveVel = waveVel * edgeFade;
    dye *= edgeFade;

    // Clamp
    height = clamp(height, -2.0, 2.0);
    waveVel = clamp(waveVel, -1.0, 1.0);
    pressure = clamp(pressure, -2.0, 2.0);
    dye = clamp(dye, 0.0, 5.0);

    // === STORE STATE ===
    textureStore(dataTextureA, coord, vec4<f32>(height, waveVel, pressure, dye));

    // === VISUALIZATION ===
    // Compute normal from height field
    let dx = (right.r - left.r) * 2.0;
    let dy = (down.r - up.r) * 2.0;
    let normal = normalize(vec3<f32>(-dx, -dy, 0.1));

    // Refraction displacement
    let refractOffset = normal.xy * 0.03;
    let sourceColor = textureSampleLevel(readTexture, u_sampler, uv + refractOffset, 0.0);

    // Phase-based rainbow coloring from wave
    let phase = atan2(waveVel, height);
    let hue = (phase / 6.283185 + 0.5);
    let amplitude = sqrt(height * height + waveVel * waveVel);
    let waveColor = hsv2rgb(vec3<f32>(hue, 0.7, amplitude * 2.0 + 0.2));

    // Dye visualization
    let dyeHue = atan2(fluidVel.y, fluidVel.x) / 6.283185 + 0.5;
    let dyeSat = smoothstep(0.0, 0.02, length(fluidVel)) * 0.8;
    let dyeVal = dye * 0.3 + 0.15;
    let dyeColor = hsv2rgb(vec3<f32>(dyeHue, dyeSat, min(dyeVal, 1.0)));

    // Lighting
    let lightDir = normalize(vec3<f32>(0.5, 0.5, 1.0));
    let diffuse = max(dot(normal, lightDir), 0.0);

    // Blend
    var finalColor = sourceColor.rgb;
    finalColor = finalColor + waveColor * amplitude * 0.5;
    finalColor = finalColor + dyeColor * 0.4;
    finalColor = finalColor * (0.5 + diffuse * 0.5);

    // Caustic bright spots
    let caustic = pow(abs(laplacian) * 5.0, 2.0);
    finalColor = finalColor + vec3<f32>(caustic * 0.2);

    finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));

    // Alpha = wave amplitude + dye density (meaningful)
    let outputAlpha = min(amplitude * 0.5 + dye * 0.2, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(finalColor, outputAlpha));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
