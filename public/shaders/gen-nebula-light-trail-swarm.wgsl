// ═══════════════════════════════════════════════════════════════════════════════
//  Nebula Light-Trail Swarm
//  Category: generative
//  Description: Photon-like particles race through the scene leaving glowing,
//               fading trails that pulse with audio. Creates a breathing nebula.
//  Features: audio-reactive, generative, mouse-driven
// ═══════════════════════════════════════════════════════════════════════════════

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

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn hash21(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += vec3<f32>(dot(p3, p3.yzx + vec3<f32>(33.33)));
    return fract((p3.xx + p3.yz) * p3.zy);
}

// Particle trail SDF
fn trailDist(uv: vec2<f32>, p: vec2<f32>, dir: vec2<f32>, len: f32, width: f32) -> f32 {
    let toP = uv - p;
    let proj = dot(toP, dir);
    let clampedProj = clamp(proj, 0.0, len);
    let closest = p + dir * clampedProj;
    return length(uv - closest) - width;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(id.xy) / res;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Parameters
    let speed = u.zoom_params.x * 2.0 + 0.5;
    let trailDecay = u.zoom_params.y * 0.9 + 0.1;
    let curlStrength = u.zoom_params.z * 3.0;
    let glowRadius = u.zoom_params.w * 0.03 + 0.005;

    // Mouse repulsion
    let mouse = u.zoom_config.yz;
    let mouseDist = length(uv - mouse);
    let repel = smoothstep(0.2, 0.0, mouseDist);

    var col = vec3<f32>(0.0);
    var totalGlow = 0.0;

    // Simulate multiple particle trails procedurally
    let numParticles = 20;
    for (var i: i32 = 0; i < numParticles; i = i + 1) {
        let fi = f32(i);
        let seed = hash21(vec2<f32>(fi, floor(time * 0.1)));

        // Particle path with curl noise
        let t = fract(time * speed * (0.3 + seed.x * 0.4) + fi * 0.1);
        let life = 1.0 - t;
        if (life < 0.01) { continue; }

        // Start position
        let startAngle = fi * 0.618 + seed.y * 6.28318;
        let startRadius = 0.1 + seed.x * 0.3;
        let startPos = vec2<f32>(cos(startAngle), sin(startAngle)) * startRadius + vec2<f32>(0.5);

        // Curl-noise displacement for organic path
        let curlPhase = time * speed * 0.5 + fi;
        let curlX = sin(curlPhase + uv.x * curlStrength) * 0.2;
        let curlY = cos(curlPhase + uv.y * curlStrength) * 0.2;

        // Direction and end position
        let dir = normalize(vec2<f32>(cos(startAngle + 1.57), sin(startAngle + 1.57)) + vec2<f32>(curlX, curlY));
        let endPos = startPos + dir * (0.1 + t * 0.4);

        // Apply mouse repulsion
        let particlePos = mix(startPos, endPos, t);
        let toMouse = particlePos - mouse;
        let distToMouse = length(toMouse);
        if (distToMouse < 0.2) {
            let push = normalize(toMouse + vec2<f32>(0.001)) * (0.2 - distToMouse) * 2.0;
            // Adjust UV check for repelled position
        }

        // Trail segment
        let trailLen = t * 0.3;
        let d = trailDist(uv, startPos, dir, trailLen, glowRadius * life);

        // Glow falloff
        let glow = smoothstep(0.02, 0.0, d) * life;

        // Color based on particle ID and audio
        let hue = fi / f32(numParticles) + bass * 0.2;
        let particleCol = vec3<f32>(
            0.5 + 0.5 * cos(6.28318 * (hue + 0.0)),
            0.5 + 0.5 * cos(6.28318 * (hue + 0.33)),
            0.5 + 0.5 * cos(6.28318 * (hue + 0.67))
        );

        // Audio boosts
        let audioBoost = 1.0 + bass * 1.5 + treble * 0.5;
        col = col + particleCol * glow * audioBoost;
        totalGlow = totalGlow + glow;
    }

    // Central nebula core
    let coreDist = length(uv - vec2<f32>(0.5));
    let coreGlow = exp(-coreDist * coreDist * 8.0) * (0.5 + bass * 0.5);
    col = col + vec3<f32>(0.4, 0.6, 1.0) * coreGlow;

    // Starfield background
    let starNoise = hash(floor(uv * 300.0));
    if (starNoise > 0.997) {
        let starBright = (starNoise - 0.997) / 0.003;
        col = col + vec3<f32>(1.0, 0.95, 0.9) * starBright * (0.5 + mids * 0.5);
    }

    col = clamp(col, vec3<f32>(0.0), vec3<f32>(3.0));

    let alpha = clamp(totalGlow * 0.5 + coreGlow, 0.0, 1.0);
    let depth = 0.5 - coreDist * 0.3;
    textureStore(writeTexture, id.xy, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
