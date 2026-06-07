// ═══════════════════════════════════════════════════════════════════
//  distortion-gravitational-prismatic
//  Category: advanced-hybrid
//  Features: gravitational-lensing, spectral-dispersion, physical-refraction
//  Complexity: Very High
//  Chunks From: distortion_gravitational_lens.wgsl, spec-prismatic-dispersion.wgsl
//  Created: 2026-04-18
//  By: Agent CB-21 — Distortion & Material Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Einstein-ring gravitational lensing combined with 4-band Cauchy
//  spectral dispersion. Each mass warps spacetime AND refracts light
//  through a prismatic accretion disk. Gravitational redshift blends
//  with wavelength-dependent IOR for physically-inspired chromatic art.
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

const PI: f32 = 3.14159265359;

// ═══ CHUNK: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

struct Mass {
    pos: vec2<f32>,
    mass: f32,
    radius: f32,
};

fn deflectionAngle(rayPos: vec2<f32>, mass: Mass) -> vec2<f32> {
    let delta = rayPos - mass.pos;
    let dist2 = dot(delta, delta);
    let dist = sqrt(dist2);
    if (dist < mass.radius * 0.1) {
        return vec2<f32>(0.0);
    }
    let deflectionMagnitude = mass.mass * mass.radius / (dist + 0.001);
    return -normalize(delta) * deflectionMagnitude;
}

fn cauchyIOR(wavelengthNm: f32, A: f32, B: f32) -> f32 {
    let lambdaUm = wavelengthNm * 0.001;
    return A + B / (lambdaUm * lambdaUm);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    let t = clamp((lambda - 440.0) / (680.0 - 440.0), 0.0, 1.0);
    let r = smoothstep(0.5, 0.8, t) + smoothstep(0.0, 0.15, t) * 0.3;
    let g = 1.0 - abs(t - 0.4) * 3.0;
    let b = 1.0 - smoothstep(0.0, 0.4, t);
    return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn accretionDiskColor(radius: f32, innerRadius: f32) -> vec3<f32> {
    let temp = pow(innerRadius / radius, 0.75);
    var color: vec3<f32>;
    if (temp > 0.8) {
        color = vec3<f32>(1.0, 0.9, 0.8);
    } else if (temp > 0.6) {
        color = vec3<f32>(1.0, 0.6, 0.3);
    } else if (temp > 0.4) {
        color = vec3<f32>(0.8, 0.2, 0.1);
    } else {
        color = vec3<f32>(0.3, 0.05, 0.05);
    }
    return color * temp * temp;
}

fn einsteinRadius(mass: f32, distance: f32) -> f32 {
    return sqrt(mass) * distance * 0.1;
}

fn toneMap(x: vec3<f32>) -> vec3<f32> {
    return x / (1.0 + x * 0.5);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let lensStrength = 0.5 + u.zoom_params.x;
    let numMasses = i32(u.zoom_params.y * 4.0) + 1;
    let diskIntensity = u.zoom_params.z;
    let cauchyB = mix(0.01, 0.08, u.zoom_params.w);

    let mousePos = u.zoom_config.yz;
    let audioPulse = u.zoom_config.w;

    var masses: array<Mass, 5>;
    masses[0] = Mass(mousePos, 2.0 + audioPulse * 2.0, 0.02 * lensStrength);
    for (var i: i32 = 1; i < 5; i = i + 1) {
        if (i < numMasses) {
            let fi = f32(i);
            let angle = time * 0.2 + fi * (2.0 * PI / f32(numMasses - 1));
            let radius = 0.2 + fi * 0.1;
            masses[i] = Mass(
                vec2<f32>(mousePos.x + cos(angle) * radius, mousePos.y + sin(angle) * radius),
                0.5, 0.01 * lensStrength
            );
        }
    }

    var rayPos = uv;
    var totalDeflection = vec2<f32>(0.0);
    for (var i: i32 = 0; i < numMasses; i = i + 1) {
        totalDeflection += deflectionAngle(rayPos, masses[i]);
    }

    // Prismatic dispersion: each wavelength deflects differently
    let WAVELENGTHS = array<f32, 4>(450.0, 520.0, 600.0, 680.0);
    var finalColor = vec3<f32>(0.0);
    var spectralResponse = vec4<f32>(0.0);

    for (var w: i32 = 0; w < 4; w = w + 1) {
        let ior = cauchyIOR(WAVELENGTHS[w], 1.5, cauchyB);
        let deflectScale = 1.0 + (ior - 1.5) * 2.0;
        let sourcePos = rayPos - totalDeflection * 0.5 * deflectScale;
        if (all(sourcePos >= vec2<f32>(0.0)) && all(sourcePos <= vec2<f32>(1.0))) {
            let sample = textureSampleLevel(readTexture, u_sampler, sourcePos, 0.0);
            let bandIntensity = dot(sample.rgb, wavelengthToRGB(WAVELENGTHS[w]));
            spectralResponse[w] = bandIntensity;
            finalColor += wavelengthToRGB(WAVELENGTHS[w]) * bandIntensity;
        }
    }

    // Accretion disk with prismatic tint
    let toPrimary = uv - masses[0].pos;
    let distPrimary = length(toPrimary);
    let innerDisk = masses[0].radius * 3.0;
    let outerDisk = masses[0].radius * 15.0;
    if (distPrimary > innerDisk && distPrimary < outerDisk) {
        let diskTemp = accretionDiskColor(distPrimary, innerDisk);
        let diskPattern = sin(atan2(toPrimary.y, toPrimary.x) * 20.0 + time * 2.0);
        let diskGlow = smoothstep(outerDisk, innerDisk, distPrimary) * (0.7 + diskPattern * 0.3);
        // Add prismatic separation to disk glow
        let prismShift = vec2<f32>(cos(time), sin(time)) * cauchyB * 0.02;
        let diskColor = diskTemp * diskGlow * diskIntensity * (1.0 + audioPulse * 2.0);
        finalColor += diskColor;
    }

    // Einstein ring with spectral glow
    let einsteinR = einsteinRadius(masses[0].mass, length(toPrimary));
    let ringDist = abs(distPrimary - einsteinR);
    let ringGlow = smoothstep(0.02, 0.0, ringDist) * lensStrength;
    let ringSpectrum = wavelengthToRGB(550.0 + sin(time * 2.0) * 100.0);
    finalColor += ringSpectrum * ringGlow * 0.5;

    // Gravitational redshift near mass
    let redshift = smoothstep(masses[0].radius * 10.0, masses[0].radius, distPrimary);
    finalColor.r += finalColor.r * redshift * 0.3;
    finalColor.b -= finalColor.b * redshift * 0.2;

    finalColor = toneMap(finalColor);
    let vignette = 1.0 - length(uv - 0.5) * 0.3;
    finalColor *= vignette;

    textureStore(writeTexture, coord, vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, coord, vec4<f32>(length(totalDeflection), 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coord, spectralResponse);
}
