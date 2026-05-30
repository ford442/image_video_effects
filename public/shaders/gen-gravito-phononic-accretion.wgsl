// ═══════════════════════════════════════════════════════════════════
//  Gravito-Phononic Accretion
//  Category: generative
//  Description: Audio-driven gravitational centers accrete procedural
//  density fields with gravitational lensing distortion. Different audio
//  bands control different gravitational bodies. Mouse adds mass.
//  Complexity: Medium-High
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
const TAU: f32 = 6.28318530718;

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn smoothNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u2 = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash12(i), hash12(i + vec2<f32>(1.0, 0.0)), u2.x),
        mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u2.x),
        u2.y
    );
}

fn fbmDensity(p: vec2<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var amp = 0.5;
    var pos = p;
    for (var i = 0; i < octaves; i++) {
        v += amp * smoothNoise(pos);
        pos *= 2.03;
        amp *= 0.5;
    }
    return v;
}

// Gravitational lensing displacement: point mass deflects ray
fn gravitationalLens(uv: vec2<f32>, massPos: vec2<f32>, mass: f32) -> vec2<f32> {
    let delta = uv - massPos;
    let dist2 = dot(delta, delta);
    let lensRadius = 0.004; // Schwarzschild-like inner radius
    if (dist2 < lensRadius * lensRadius) {
        return vec2<f32>(0.0); // inside event horizon
    }
    // Einstein ring deflection: displacement proportional to mass / dist^2
    return -normalize(delta) * mass / (dist2 + 0.001) * 0.003;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let aspect = res.x / res.y;
    let uvA = vec2<f32>(uv.x * aspect, uv.y);

    let t = u.config.x;
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let massScale   = u.zoom_params.x * 3.0 + 0.5;   // 0.5..3.5
    let numBodies   = u.zoom_params.y * 4.0 + 2.0;    // 2..6 gravitational bodies
    let lensStrength = u.zoom_params.z * 2.0 + 0.5;   // 0.5..2.5
    let densityAmt  = u.zoom_params.w * 1.5 + 0.5;    // 0.5..2.0

    let mousePos = vec2<f32>(u.zoom_config.y * aspect, u.zoom_config.z);

    // Compute total gravitational lensing displacement
    var lensDisplace = vec2<f32>(0.0);
    let nBodies = i32(clamp(numBodies, 2.0, 6.0));

    // Different audio bands control different bodies
    let audioBands = array<f32, 6>(bass, mids, treble,
                                   bass * mids, mids * treble, bass * treble);

    for (var i = 0; i < nBodies; i++) {
        let fi = f32(i);
        let bodySeed = hash22(vec2<f32>(fi + 0.5, fi * 2.3 + 1.0));
        let audioAmp = audioBands[i];

        // Bodies orbit and breathe with audio
        let orbitR = 0.15 + bodySeed.x * 0.25 + audioAmp * 0.1;
        let orbitSpd = 0.15 + fi * 0.08;
        let bodyX = 0.5 * aspect + orbitR * cos(t * orbitSpd + bodySeed.y * TAU);
        let bodyY = 0.5 + orbitR * 0.6 * sin(t * orbitSpd * 0.7 + bodySeed.x * TAU);
        let bodyPos = vec2<f32>(bodyX, bodyY);

        // Mass grows with associated audio band
        let bodyMass = massScale * (0.3 + audioAmp * 0.7) * lensStrength;

        lensDisplace += gravitationalLens(uvA, bodyPos, bodyMass);
    }

    // Mouse creates an additional temporary gravitational body
    let mouseMass = massScale * bass * 0.8 * lensStrength;
    lensDisplace += gravitationalLens(uvA, mousePos, mouseMass);

    // Apply lensing to sample position
    let lensedUV = uvA + lensDisplace * 20.0;

    // Sample procedural density field at lensed position
    let density = fbmDensity(lensedUV * 3.0 + vec2<f32>(t * 0.04, 0.0), 5);
    let densityB = fbmDensity(lensedUV * 5.0 - vec2<f32>(t * 0.06, t * 0.03), 4);

    // Accretion disk: radial density accumulation around each body
    var accretion = 0.0;
    var totalMass = 0.0;
    for (var i = 0; i < nBodies; i++) {
        let fi = f32(i);
        let bodySeed = hash22(vec2<f32>(fi + 0.5, fi * 2.3 + 1.0));
        let audioAmp = audioBands[i];
        let orbitR = 0.15 + bodySeed.x * 0.25 + audioAmp * 0.1;
        let orbitSpd = 0.15 + fi * 0.08;
        let bodyX = 0.5 * aspect + orbitR * cos(t * orbitSpd + bodySeed.y * TAU);
        let bodyY = 0.5 + orbitR * 0.6 * sin(t * orbitSpd * 0.7 + bodySeed.x * TAU);
        let bodyPos = vec2<f32>(bodyX, bodyY);

        let dist = length(uvA - bodyPos);
        let bodyMass = massScale * (0.3 + audioAmp * 0.7);
        totalMass += bodyMass;

        // Disk profile: toroidal distribution
        let diskInner = 0.02 + audioAmp * 0.01;
        let diskOuter = 0.15 + audioAmp * 0.08;
        let diskProfile = smoothstep(diskOuter, diskInner * 2.0, dist) *
                          smoothstep(diskInner * 0.5, diskInner, dist);

        // Orbital shear: density streaks
        let angle = atan2(uvA.y - bodyPos.y, uvA.x - bodyPos.x);
        let shear = sin(angle * 3.0 + t * (1.0 + fi * 0.3) + audioAmp * PI) * 0.5 + 0.5;

        accretion += diskProfile * bodyMass * shear * densityAmt;
    }

    // Dark core inside Schwarzschild radius
    let coreBlackout = 1.0; // will be applied per body via lensing

    // Base color: dark cosmic void
    var color = vec3<f32>(0.01, 0.01, 0.02);

    // Filamentary gas structure from density field
    let gasColor1 = vec3<f32>(0.4 + bass * 0.3, 0.15, 0.5 + mids * 0.2); // purple nebula
    let gasColor2 = vec3<f32>(0.7 + treble * 0.2, 0.4 + mids * 0.1, 0.1); // orange accretion
    let gasBlend = mix(gasColor1, gasColor2, density);
    color += gasBlend * density * densityAmt * 0.4;
    color += gasColor2 * densityB * accretion * 0.8;

    // Lensing artifacts: bright arcs
    let lensArc = length(lensDisplace) * 200.0;
    color += vec3<f32>(0.9, 0.7, 0.3) * smoothstep(0.5, 1.5, lensArc) * treble;

    // Stellar background: faint point stars
    let starNoise = hash12(uvA * 400.0 + vec2<f32>(1.3, 2.7));
    if (starNoise > 0.985) {
        color += vec3<f32>(0.8, 0.9, 1.0) * (starNoise - 0.985) * 50.0;
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(1.0)), 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
}
