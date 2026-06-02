// ═══════════════════════════════════════════════════════════════════
//  Symbiotic Light Propagation Networks
//  Category: generative
//  Description: Network of light-conducting organic structures growing,
//  competing and supporting each other while transporting and transforming
//  light. Audio influences color, intensity, and transmission rules.
//  Mouse seeds or prunes the network.
//  Complexity: High
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

fn hash32(p: vec3<f32>) -> vec2<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
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

// Physarum-like slime mold trace: network segment
fn networkSegment(uv: vec2<f32>, nodeA: vec2<f32>, nodeB: vec2<f32>,
                  width: f32, t: f32, bass: f32) -> f32 {
    let ab = nodeB - nodeA;
    let len = length(ab);
    if (len < 0.001) { return 0.0; }
    let dir = ab / len;
    let toUV = uv - nodeA;
    let proj = clamp(dot(toUV, dir), 0.0, len);
    let closest = nodeA + dir * proj;
    let dist = length(uv - closest);

    // Pulse: light travelling along the segment
    let pulsePhase = proj / len - t * 0.5 * (1.0 + bass * 0.5);
    let pulse = 0.5 + 0.5 * sin(pulsePhase * TAU * 3.0);

    // Segment intensity: tapered + pulsing
    let taper = sin(clamp(proj / len, 0.0, 1.0) * PI);
    return smoothstep(width, 0.0, dist) * (0.5 + 0.5 * pulse) * taper;
}

// Network node glow
fn nodeGlow(uv: vec2<f32>, nodePos: vec2<f32>, radius: f32, t: f32,
            bass: f32, treble: f32) -> f32 {
    let d = length(uv - nodePos);
    let pulse = 0.5 + 0.5 * sin(t * 3.0 + hash12(nodePos * 10.0) * TAU + bass * PI);
    return smoothstep(radius * (1.0 + treble * 0.3), 0.0, d) * (0.5 + pulse * 0.5);
}

// Competition: overlapping networks suppress each other
fn networkCompetition(brightness1: f32, brightness2: f32, competition: f32) -> vec2<f32> {
    let competitive = competition;
    let symbiotic = 1.0 - competition;

    // Competitive: stronger suppresses weaker
    let suppress1 = 1.0 - brightness2 * competitive;
    let suppress2 = 1.0 - brightness1 * competitive;

    // Symbiotic: together they amplify
    let amplify = 1.0 + (brightness1 + brightness2) * symbiotic * 0.5;

    return vec2<f32>(
        brightness1 * suppress1 * amplify,
        brightness2 * suppress2 * amplify
    );
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

    let networkDensity = u.zoom_params.x * 2.0 + 0.5;   // 0.5..2.5
    let competition    = u.zoom_params.y;                 // 0=symbiotic, 1=competitive
    let lightIntensity = u.zoom_params.z * 2.0 + 0.5;   // 0.5..2.5
    let growthAmt      = u.zoom_params.w;                 // 0..1 growth vs mature

    let mousePos = vec2<f32>(u.zoom_config.y * aspect, u.zoom_config.z);
    let mouseDist = length(uvA - mousePos);
    // Mouse seeds new nodes or prunes existing network
    let mouseRadius = 0.08 + bass * 0.03;
    let mouseSeed = exp(-mouseDist * mouseDist * 15.0);

    // Generate two competing/symbiotic network species
    let numNodes = i32(clamp(networkDensity * 8.0 + 4.0, 4.0, 16.0));
    var network1 = 0.0;
    var network2 = 0.0;
    var nodeLight1 = 0.0;
    var nodeLight2 = 0.0;

    // Species 1: cool bioluminescent blue-green
    for (var i = 0; i < numNodes; i++) {
        let fi = f32(i);
        let seed1 = hash22(vec2<f32>(fi * 0.3 + 0.1, fi * 0.7));
        let birthTime = seed1.x * 3.0;
        let age = clamp(t * 0.1 - birthTime, 0.0, 1.0) * (1.0 - growthAmt * 0.3);

        // Node positions: slowly drift with bass
        let nodePos1 = vec2<f32>(
            seed1.x * aspect + sin(t * 0.08 + fi * 1.3 + bass * 0.5) * 0.05 * aspect,
            seed1.y + cos(t * 0.06 + fi * 0.9 + mids * 0.3) * 0.05
        );

        // Node seeded near mouse
        let nodePos1M = mix(nodePos1, mousePos, mouseSeed * 0.3);

        // Node glow
        let ng = nodeGlow(uvA, nodePos1M, 0.015 + mids * 0.01, t, bass, treble) * age;
        nodeLight1 += ng;

        // Connect to neighbors: filamentary light transport
        for (var j = i + 1; j < numNodes; j++) {
            let fj = f32(j);
            let seed2 = hash22(vec2<f32>(fj * 0.3 + 0.1, fj * 0.7));
            let nodePos2 = vec2<f32>(
                seed2.x * aspect + sin(t * 0.08 + fj * 1.3 + bass * 0.5) * 0.05 * aspect,
                seed2.y + cos(t * 0.06 + fj * 0.9 + mids * 0.3) * 0.05
            );
            let dist12 = length(nodePos1M - nodePos2);
            // Only connect nearby nodes
            let maxDist = (0.25 + mids * 0.1) * aspect;
            if (dist12 < maxDist) {
                let segWidth = 0.004 + treble * 0.002;
                let strength = (1.0 - dist12 / maxDist) * age;
                network1 += networkSegment(uvA, nodePos1M, nodePos2, segWidth, t, bass) * strength;
            }
        }
    }

    // Species 2: warm bioluminescent pink-gold
    for (var i = 0; i < numNodes; i++) {
        let fi = f32(i);
        let seed1 = hash22(vec2<f32>(fi * 0.5 + 5.3, fi * 0.8 + 2.1));
        let birthTime = seed1.x * 2.0 + 1.0;
        let age = clamp(t * 0.1 - birthTime, 0.0, 1.0) * (1.0 - growthAmt * 0.2);

        let nodePos1 = vec2<f32>(
            seed1.x * aspect + cos(t * 0.09 + fi * 1.1 + treble * 0.4) * 0.06 * aspect,
            seed1.y + sin(t * 0.07 + fi * 0.8 + bass * 0.2) * 0.06
        );

        let ng = nodeGlow(uvA, nodePos1, 0.012 + treble * 0.008, t, bass, treble) * age;
        nodeLight2 += ng;

        for (var j = i + 1; j < numNodes; j++) {
            let fj = f32(j);
            let seed2 = hash22(vec2<f32>(fj * 0.5 + 5.3, fj * 0.8 + 2.1));
            let nodePos2 = vec2<f32>(
                seed2.x * aspect + cos(t * 0.09 + fj * 1.1 + treble * 0.4) * 0.06 * aspect,
                seed2.y + sin(t * 0.07 + fj * 0.8 + bass * 0.2) * 0.06
            );
            let dist12 = length(nodePos1 - nodePos2);
            let maxDist = (0.28 + treble * 0.1) * aspect;
            if (dist12 < maxDist) {
                let segWidth = 0.003 + bass * 0.002;
                let strength = (1.0 - dist12 / maxDist) * age;
                network2 += networkSegment(uvA, nodePos1, nodePos2, segWidth, t, treble) * strength;
            }
        }
    }

    // Apply competition/symbiosis
    let netResult = networkCompetition(clamp(network1, 0.0, 1.0),
                                        clamp(network2, 0.0, 1.0), competition);
    let n1 = netResult.x;
    let n2 = netResult.y;

    // Background: deep void with subtle organic texture
    let bgTexture = smoothNoise(uvA * 15.0 + vec2<f32>(t * 0.01, 0.0)) * 0.03;
    var color = vec3<f32>(0.01 + bgTexture, 0.02 + bgTexture, 0.04 + bgTexture * 1.5);

    // Species 1: bioluminescent cyan-green filaments
    let col1 = vec3<f32>(0.05 + bass * 0.1, 0.8 + mids * 0.2, 0.5 + treble * 0.3);
    color += col1 * n1 * lightIntensity * 0.8;
    color += col1 * 1.2 * nodeLight1 * lightIntensity;

    // Species 2: warm bioluminescent amber-pink filaments
    let col2 = vec3<f32>(0.9 + treble * 0.1, 0.4 + bass * 0.2, 0.2 + mids * 0.3);
    color += col2 * n2 * lightIntensity * 0.7;
    color += col2 * 1.0 * nodeLight2 * lightIntensity;

    // Intersection zones: color mixing creates complex light transport
    let intersection = n1 * n2;
    let mixedLight = mix(col1, col2, 0.5) + vec3<f32>(0.3, 0.2, 0.5) * mids;
    color += mixedLight * intersection * lightIntensity * 2.0;

    // Mouse influence: bright seeding pulse
    color += mix(col1, col2, 0.5) * mouseSeed * (0.4 + bass * 0.3) * lightIntensity;

    // Ambient bioluminescence flicker
    let flicker = 0.5 + 0.5 * sin(t * 7.0 + uvA.x * 3.0 + bass * PI);
    color *= 0.9 + flicker * 0.1 * treble;

    // Vignette
    let vig = 1.0 - smoothstep(0.25, 0.75, length(uv - 0.5) * 1.4);
    color *= vig;

    textureStore(writeTexture, global_id.xy, vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(1.0)), 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
}
