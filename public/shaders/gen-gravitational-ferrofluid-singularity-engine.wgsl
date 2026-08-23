// ----------------------------------------------------------------
// Gravitational Ferrofluid Singularity-Engine
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Singularity Mass, .y = Fluid Viscosity, .z = Spike Density, .w = Iridescence
  ripples: array<vec4<f32>, 50>,
};

// --- CORE ALGORITHM ---

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash(p: vec3<f32>) -> f32 {
    let q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q.x) * 43758.5453123);
}

fn noise3D(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(hash(i + vec3<f32>(0.0, 0.0, 0.0)), hash(i + vec3<f32>(1.0, 0.0, 0.0)), u.x),
            mix(hash(i + vec3<f32>(0.0, 1.0, 0.0)), hash(i + vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y),
        mix(mix(hash(i + vec3<f32>(0.0, 0.0, 1.0)), hash(i + vec3<f32>(1.0, 0.0, 1.0)), u.x),
            mix(hash(i + vec3<f32>(0.0, 1.0, 1.0)), hash(i + vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y), u.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn sdf(p: vec3<f32>, singularityMass: f32, fluidViscosity: f32, spikeDensity: f32) -> f32 {
    let time = u.config.x;

    // Base sphere representing the core of the singularity
    let baseSphere = length(p) - (1.0 + singularityMass * 0.5);

    // Rotate the magnetic domain around the horizon instead of calculating and
    // discarding it. Two counter-moving angular fronts rake the fluid surface.
    var distortedP = p;
    let dist = length(p);
    let angle = time * (0.8 + fluidViscosity * 2.4) + 1.0 / (dist + 0.1);
    let r2 = rot(angle);
    distortedP = vec3<f32>(r2 * distortedP.xy, distortedP.z);
    let angularFront = sin(atan2(distortedP.y, distortedP.x) * (5.0 + spikeDensity * 2.0) - time * 8.0);
    let radialFront = sin(dist * 15.0 - time * (9.0 + fluidViscosity * 5.0));

    // Magnetic spikes use the rotated domain and remain bounded at the core.
    let noiseVal = noise3D(distortedP * spikeDensity * 4.0 + vec3<f32>(0.0, 0.0, time * fluidViscosity * 2.0));
    let spikes = (noiseVal - 0.5) * 0.65 + angularFront * radialFront * 0.12;

    // Combine base sphere with spikes
    return baseSphere + spikes * smoothstep(0.5, 2.0, dist);
}

fn getNormal(p: vec3<f32>, singularityMass: f32, fluidViscosity: f32, spikeDensity: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        sdf(p + e.xyy, singularityMass, fluidViscosity, spikeDensity) - sdf(p - e.xyy, singularityMass, fluidViscosity, spikeDensity),
        sdf(p + e.yxy, singularityMass, fluidViscosity, spikeDensity) - sdf(p - e.yxy, singularityMass, fluidViscosity, spikeDensity),
        sdf(p + e.yyx, singularityMass, fluidViscosity, spikeDensity) - sdf(p - e.yyx, singularityMass, fluidViscosity, spikeDensity)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let resolution = vec2<f32>(u.config.zw);

    if (pixel.x >= i32(resolution.x) || pixel.y >= i32(resolution.y)) { return; }

    let uv = (vec2<f32>(pixel) - resolution * 0.5) / min(resolution.x, resolution.y);
    let time = u.config.x;

    // Mouse Interaction
    let mouse = u.zoom_config.yz; // .yz = mouse_uv
    let mouseDown = u.zoom_config.w > 0.5;

    // Map mouse UV (0..1) to screen space (-aspect..aspect, -1..1)
    let aspect = resolution.x / resolution.y;
    var mousePos = (mouse - 0.5) * 2.0;
    mousePos.x *= aspect;

    // Audio Reactivity
    let audioBands = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
    let bass = audioBands.x;
    let mids = audioBands.y;
    let treble = audioBands.z;
    let audioPulse = 1.0 + bass * 0.2;

    // Parameters
    let singularityMass = u.zoom_params.x * audioPulse;
    let fluidViscosity = u.zoom_params.y;
    let spikeDensity = u.zoom_params.z;
    let iridescence = u.zoom_params.w;

    // Ray Setup
    let ro = vec3<f32>(0.0, 0.0, 5.0);
    let rd = normalize(vec3<f32>(uv, -1.0));

    // Gravity Well Distortion (Mouse)
    let mouse3D = vec3<f32>(mousePos * 2.0, 0.0); // Simple projection

    // Raymarching Loop
    var dO = 0.0;
    var p = ro;
    var hit = false;
    for (var i = 0; i < 100; i++) {
        p = ro + rd * dO;

        // Gravity distortion effect on ray position
        let distToMouse = length(p - mouse3D);
        var pull = 0.5;
        if (mouseDown) { pull = 2.0; }
        let warp = normalize(mouse3D - p + vec3<f32>(0.001)) * (pull / (distToMouse * distToMouse + 0.1));
        p += warp;

        let dS = sdf(p, singularityMass, fluidViscosity, spikeDensity);
        dO += dS * 0.5; // step size mitigation for distortion

        if (dS < 0.001) { hit = true; break; }
        if (dO > 20.0) { break; }
    }

    // Shading
    var color = vec3<f32>(0.01, 0.01, 0.02); // Quantum foam background base

    // Simple quantum foam background noise
    let bgNoise = noise3D(vec3<f32>(uv * 10.0, time * 0.5));
    color += vec3<f32>(0.05, 0.05, 0.1) * bgNoise;

    if (hit) {
        let n = getNormal(p, singularityMass, fluidViscosity, spikeDensity);
        let v = -rd; // view vector

        // Base color: Obsidian
        let baseColor = vec3<f32>(0.05, 0.05, 0.05);

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 1.0, 1.0));
        let diff = max(dot(n, lightDir), 0.0);

        // Specular
        let r = reflect(-lightDir, n);
        let spec = pow(max(dot(v, r), 0.0), 32.0);

        // Iridescence Rim Light based on view angle and distance to center
        let distToCenter = length(p);
        let rim = 1.0 - max(dot(v, n), 0.0);
        let rimPow = pow(rim, 3.0);

        // Cosmic radiation palette shifting based on iridescence parameter and normal
        let colorShift = time * 0.5 + n.y * 2.0 + iridescence * 3.14;
        let iridColor = vec3<f32>(
            0.5 + 0.5 * sin(colorShift),
            0.5 + 0.5 * sin(colorShift + 2.0),
            0.5 + 0.5 * sin(colorShift + 4.0)
        );

        let glowIntensity = smoothstep(2.5, 0.5, distToCenter); // Intense near singularity

        color = baseColor * diff + spec * vec3<f32>(1.0) + iridColor * rimPow * glowIntensity * 2.0;
    }

    // Event horizon lensing overlay
    if (!hit) {
        let distToCenter = length(uv);
        if (distToCenter < singularityMass * 0.5) {
             color = vec3<f32>(0.0); // Black hole core
        } else {
             // Lensing distortion of background
             let lens = (singularityMass * 0.1) / (distToCenter * distToCenter + 0.01);
             let bgUV = uv * (1.0 - lens);
             let lensedNoise = noise3D(vec3<f32>(bgUV * 10.0, time * 0.5));
             color = mix(color, vec3<f32>(0.1, 0.2, 0.4) * lensedNoise, smoothstep(1.0, 0.0, distToCenter - singularityMass * 0.5));
        }
    }

    // Click ripples effect overlay
    var rippleGlow = 0.0;
    let screenUV = vec2<f32>(pixel) / resolution;
    let aspectFix = vec2<f32>(resolution.x / resolution.y, 1.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var r = 0u; r < rippleCount; r++) {
        let rp = u.ripples[r];
        let age = time - rp.z;
        if (age < 0.0 || age > 2.5) { continue; }
        let band = length((screenUV - rp.xy) * aspectFix) - age * 0.45;
        let intensity = max(0.0, 1.0 - abs(band) * 30.0) * (1.0 - age / 2.5);
        rippleGlow += intensity;
    }
    color += vec3<f32>(0.2, 0.5, 1.0) * rippleGlow;

    // Accelerating ferrofluid droplets: fixed identities, smooth analytic
    // trajectories, and velocity-stretched fronts rather than frame hashes.
    var dropletGlow = 0.0;
    for (var i = 0; i < 8; i++) {
        let fi = f32(i);
        let seed = hash(vec3<f32>(fi, fi * 1.71, 3.4));
        let phase = fract(time * (0.22 + seed * 0.16) + seed);
        let accel = phase * phase;
        let ang = fi * 2.39996 + time * (1.3 + mids * 0.5);
        let dir = vec2<f32>(cos(ang), sin(ang));
        let center = dir * (0.32 + accel * 1.35);
        let local = uv - center;
        let along = dot(local, dir);
        let across = abs(dot(local, vec2<f32>(-dir.y, dir.x)));
        let streak = exp(-across * across * 900.0) * exp(-abs(along + 0.08) * 18.0) * smoothstep(0.0, 0.15, phase) * (1.0 - phase);
        dropletGlow += streak;
    }
    color += vec3<f32>(0.18, 0.55, 1.2) * dropletGlow * (0.5 + iridescence) * (1.0 + treble * 0.35);

    // Advect prior display light around the event horizon and show the bounded
    // result. A is the next display history; B remains untouched.
    let radial = normalize(uv + vec2<f32>(0.0001));
    let tangent = vec2<f32>(-radial.y, radial.x);
    let historyUV = clamp(screenUV - tangent * (0.004 + fluidViscosity * 0.006) - radial * 0.002, vec2<f32>(0.002), vec2<f32>(0.998));
    let maxHistoryCoord = vec2<i32>(i32(resolution.x) - 1, i32(resolution.y) - 1);
    let historyCoord = clamp(vec2<i32>(historyUV * resolution), vec2<i32>(0), maxHistoryCoord);
    let previous = textureLoad(dataTextureC, historyCoord, 0).rgb;
    let temporal = clamp(max(color, previous * (0.84 + 0.08 * iridescence)), vec3<f32>(0.0), vec3<f32>(6.0));
    let mapped = acesToneMap(temporal * 1.05);
    let depth = select(1.0, clamp(dO / 20.0, 0.0, 0.995), hit);
    let luma = dot(mapped, vec3<f32>(0.2126, 0.7152, 0.0722));
    let hitMask = select(0.0, 1.0, hit);
    let alpha = clamp(0.06 + hitMask * 0.66 + luma * 0.2 + rippleGlow * 0.08 + dropletGlow * 0.05, 0.0, 0.98);
    textureStore(dataTextureA, pixel, vec4<f32>(mapped, alpha));
    textureStore(writeTexture, pixel, vec4<f32>(mapped, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
