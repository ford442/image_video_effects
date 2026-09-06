// ═══════════════════════════════════════════════════════════════════
//  chroma-vortex-coupled
//  Category: advanced-hybrid
//  Features: chroma-vortex, fluid-coupling, mouse-driven, temporal
//  Ideas: Cauchy prismatic dispersion streamline ribbons, acoustic vortex cavitation glints, fluid rate-of-strain birefringence
//  A packing: fluid transport state [vel.x, vel.y, vorticity, density]
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

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

// Exact bilinear load from dataTextureC to avoid unfiltered sampler dependencies
fn sampleFluidExact(uv: vec2<f32>, dims: vec2<i32>) -> vec4<f32> {
    let fCoord = uv * vec2<f32>(dims) - 0.5;
    let iCoord = vec2<i32>(floor(fCoord));
    let f = fract(fCoord);

    let c00 = clamp(iCoord, vec2<i32>(0), dims - vec2<i32>(1));
    let c10 = clamp(iCoord + vec2<i32>(1, 0), vec2<i32>(0), dims - vec2<i32>(1));
    let c01 = clamp(iCoord + vec2<i32>(0, 1), vec2<i32>(0), dims - vec2<i32>(1));
    let c11 = clamp(iCoord + vec2<i32>(1, 1), vec2<i32>(0), dims - vec2<i32>(1));

    let s00 = textureLoad(dataTextureC, c00, 0);
    let s10 = textureLoad(dataTextureC, c10, 0);
    let s01 = textureLoad(dataTextureC, c01, 0);
    let s11 = textureLoad(dataTextureC, c11, 0);

    return mix(mix(s00, s10, f.x), mix(s01, s11, f.x), f.y);
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let dims = vec2<i32>(res);
    let coord = vec2<i32>(gid.xy);
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let aspect = res.x / max(res.y, 1.0);
    let time = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Single-writer spring-damper cursor for fluid vortex eye in extraBuffer[133..138]
    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    var sprungMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var mouseVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) {
        sprungMouse = rawMouse;
        mouseVel = vec2<f32>(0.0);
    }
    let dt = select(0.016, clamp(time - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
    let omega = 9.0;
    mouseVel += ((rawMouse - sprungMouse) * (omega * omega) - mouseVel * (2.0 * omega)) * dt;
    sprungMouse += mouseVel * dt;

    if (gid.x == 0u && gid.y == 0u && arrayLength(&extraBuffer) > 138u) {
        extraBuffer[133] = sprungMouse.x;
        extraBuffer[134] = sprungMouse.y;
        extraBuffer[135] = mouseVel.x;
        extraBuffer[136] = mouseVel.y;
        extraBuffer[137] = 1.0;
        extraBuffer[138] = time;
    }

    let mousePos = sprungMouse;
    let mouseSpeed = length(mouseVel);

    // Sliders
    let twist = (u.zoom_params.x * 4.0 - 2.0) * 3.14159 * (1.0 + bass * 0.4);
    let spread = u.zoom_params.y * 0.12 * (1.0 + treble * 0.5);
    let radius = max(u.zoom_params.z * 0.8 + 0.05, 0.02);
    let centerBias = u.zoom_params.w;

    let viscosity = mix(0.92, 0.99, clamp(u.zoom_params.x * 0.5 + 0.5, 0.0, 1.0));
    let mouseRadius = mix(0.04, 0.2, u.zoom_params.y);
    let vortexStrength = (u.zoom_params.w * 3.0 + 0.5);

    let px = vec2<f32>(1.0) / res;
    let currentFluid = sampleFluidExact(uv, dims);
    let prevVel = currentFluid.xy;

    // Semi-Lagrangian advection step with exact bilinear sampling
    let backUV = clamp(uv - prevVel * px * 2.0, vec2<f32>(0.0), vec2<f32>(1.0));
    let advectedFluid = sampleFluidExact(backUV, dims);
    var vel = advectedFluid.xy * viscosity;
    var dens = advectedFluid.w * viscosity;

    // Mouse vortex stirring
    let toMouse = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let distMouse = length(toMouse);
    let influence = smoothstep(mouseRadius, 0.0, distMouse);

    vel += mouseVel * influence * 0.6;
    let vortexDir = vec2<f32>(-mouseVel.y, mouseVel.x);
    vel += vortexDir * influence * vortexStrength * (mouseSpeed + 0.1);

    // Click shockwaves inject outward momentum and density burst
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let elapsed = time - ripple.z;
        if (elapsed > 0.0 && elapsed < 2.2) {
            let rToMouse = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let rDist = length(rToMouse);
            let rInfluence = smoothstep(0.25, 0.0, rDist) * exp(-elapsed * 1.6);
            let outward = select(vec2<f32>(0.0), normalize(rToMouse / vec2<f32>(aspect, 1.0)), rDist > 0.001);
            vel += outward * rInfluence * 0.4;
            dens += rInfluence * 0.6;
        }
    }

    // Boundary damping
    let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    let edgeDamp = smoothstep(0.02, 0.08, edgeDist);
    vel *= edgeDamp;
    vel = clamp(vel, vec2<f32>(-0.6), vec2<f32>(0.6));
    dens = clamp(dens, 0.0, 3.0);

    // Estimate spatial derivatives of velocity field for vorticity and strain rate
    let velR = sampleFluidExact(clamp(uv + vec2<f32>(px.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), dims).xy;
    let velL = sampleFluidExact(clamp(uv - vec2<f32>(px.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), dims).xy;
    let velU = sampleFluidExact(clamp(uv + vec2<f32>(0.0, px.y), vec2<f32>(0.0), vec2<f32>(1.0)), dims).xy;
    let velD = sampleFluidExact(clamp(uv - vec2<f32>(0.0, px.y), vec2<f32>(0.0), vec2<f32>(1.0)), dims).xy;

    let dvx_dx = (velR.x - velL.x) * 0.5;
    let dvx_dy = (velU.x - velD.x) * 0.5;
    let dvy_dx = (velR.y - velL.y) * 0.5;
    let dvy_dy = (velU.y - velD.y) * 0.5;

    let vorticity = dvy_dx - dvx_dy;

    // Store physical fluid transport state in dataTextureA
    textureStore(dataTextureA, coord, vec4<f32>(vel, vorticity, dens));

    // Optical vortex swirl sampling
    let fluidDisp = vel * (dens * 0.08 + 0.02);
    let displacedUV = uv + fluidDisp;
    let diff = displacedUV - mousePos;
    let dist = length(vec2<f32>(diff.x * aspect, diff.y));
    var factor = smoothstep(radius, 0.0, dist);
    let power = centerBias * 4.8 + 0.2;
    factor = pow(factor, power);

    // IDEA 1: Cauchy prismatic dispersion streamline ribbons
    // Vorticity curl dynamically shears R, G, B sampling angles into continuous spectral ribbons
    let curlShear = vorticity * 12.0 * factor;
    let angleBase = factor * twist + curlShear;
    let angleR = angleBase - spread * factor * 12.0;
    let angleG = angleBase;
    let angleB = angleBase + spread * factor * 12.0;

    let diffSq = vec2<f32>(diff.x * aspect, diff.y);
    let rotR = vec2<f32>(rotate(diffSq, angleR).x / aspect, rotate(diffSq, angleR).y);
    let rotG = vec2<f32>(rotate(diffSq, angleG).x / aspect, rotate(diffSq, angleG).y);
    let rotB = vec2<f32>(rotate(diffSq, angleB).x / aspect, rotate(diffSq, angleB).y);

    let uvR = clamp(mousePos + rotR, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(mousePos + rotG, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(mousePos + rotB, vec2<f32>(0.0), vec2<f32>(1.0));

    let colR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let colG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let colB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;
    var outColor = vec3<f32>(colR, colG, colB);

    // IDEA 2: Acoustic vortex cavitation glints
    // High velocity shear / low pressure vortex eye triggers acoustic micro-cavitation glints
    let kineticPressure = dot(vel, vel) * 8.0 + abs(vorticity) * 4.0;
    let cavitationNoise = fract(sin(dot(uv * 400.0 + time * 6.0, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    let cavitationGlint = pow(cavitationNoise, 32.0) * smoothstep(0.1, 0.8, kineticPressure) * (1.0 + treble * 2.0);
    outColor += vec3<f32>(0.8, 0.95, 1.3) * cavitationGlint * 1.5;

    // IDEA 3: Fluid rate-of-strain birefringence fringes
    // Symmetric rate-of-strain tensor: S_ij = 0.5 * (dv_i/dx_j + dv_j/dx_i)
    let shearStrain = 0.5 * (dvx_dy + dvy_dx);
    let normalStrain = dvx_dx - dvy_dy;
    let strainIntensity = sqrt(shearStrain * shearStrain + normalStrain * normalStrain);
    let strainRetardation = strainIntensity * 40.0;
    let birefringenceFringes = 0.5 + 0.5 * cos(strainRetardation + vec3<f32>(0.0, 2.094, 4.188));
    outColor += birefringenceFringes * smoothstep(0.02, 0.2, strainIntensity) * (0.3 + mids * 0.4);

    // Fluid tint and specular highlights
    let fluidTint = mix(vec3<f32>(1.0), vec3<f32>(0.9, 0.82, 1.1), clamp(dens * 0.4, 0.0, 0.6));
    outColor *= fluidTint;

    let specNoise = fract(sin(dot(uv * 280.0 + time * 2.5, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    let specular = pow(specNoise, 18.0) * influence * (dens + 0.2) * 2.5;
    outColor += vec3<f32>(0.9, 0.95, 1.0) * specular;

    let finalRGB = acesFilm(max(outColor, vec3<f32>(0.0)));
    let alpha = clamp(0.75 + dens * 0.15 + factor * 0.1, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(finalRGB, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth * (1.0 - factor * 0.15), 0.0, 0.0, 0.0));
}
