// ----------------------------------------------------------------
// Raptor Mini - Territorial Predator Simulation
// Category: generative
// ----------------------------------------------------------------
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

fn hash21(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += vec3<f32>(dot(p3, p3.yzx + vec3<f32>(33.33)));
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var freq = 1.0;
    var pp = p;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value += amplitude * fract(sin(dot(pp * freq, vec2<f32>(12.9898, 78.233))) * 43758.5453);
        pp = pp * 2.0 + vec2<f32>(1.7, 3.2);
        amplitude *= 0.5;
    }
    return value;
}

fn sdCapsule(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn voronoi(uv: vec2<f32>, t: f32) -> vec2<f32> {
    let n = floor(uv);
    let f = fract(uv);
    var minDist = 100.0;
    var cellId = 0.0;
    for (var j: i32 = -1; j <= 1; j = j + 1) {
        for (var i: i32 = -1; i <= 1; i = i + 1) {
            let g = vec2<f32>(f32(i), f32(j));
            let o = hash21(n + g);
            let anim = vec2<f32>(cos(t + o.x * 6.2831853), sin(t + o.y * 6.2831853)) * 0.3;
            let r = g + anim - f;
            let d = dot(r, r);
            if (d < minDist) {
                minDist = d;
                cellId = o.x;
            }
        }
    }
    return vec2<f32>(sqrt(minDist), cellId);
}

fn accumulateScent(uv: vec2<f32>, raptorPos: vec2<f32>, strength: f32) -> f32 {
    let d = length(uv - raptorPos);
    let trail = exp(-d * 12.0) * strength;
    let windDrift = sin(uv.x * 4.0 + uv.y * 3.0) * 0.1;
    let temporalDecay = exp(-length(uv - raptorPos * 0.5 + windDrift) * 0.5);
    return trail * temporalDecay;
}

fn grayScottRD(uv: vec2<f32>, feed: f32, kill: f32) -> vec2<f32> {
    let uChem = fbm(uv * 3.0, 2);
    let vChem = fbm(uv * 3.0 + vec2<f32>(5.2, 1.3), 2);
    let n1 = fbm(uv + vec2<f32>(0.01, 0.0), 3);
    let n2 = fbm(uv + vec2<f32>(0.0, 0.01), 3);
    let n3 = fbm(uv - vec2<f32>(0.01, 0.0), 3);
    let n4 = fbm(uv - vec2<f32>(0.0, 0.01), 3);
    let laplacian = (n1 + n2 + n3 + n4) * 0.25 - fbm(uv, 3);
    let reaction = uChem * vChem * vChem;
    let du = 0.2 * laplacian - reaction + feed * (1.0 - uChem);
    let dv = 0.1 * laplacian + reaction - (feed + kill) * vChem;
    return vec2<f32>(clamp(du + uChem, 0.0, 1.0), clamp(dv + vChem, 0.0, 1.0));
}

fn pursuitVector(predator: vec2<f32>, prey: vec2<f32>, speed: f32) -> vec2<f32> {
    let diff = prey - predator;
    let dist = length(diff);
    let dir = diff / max(dist, 0.001);
    return dir * speed * (1.0 + 1.0 / max(dist, 0.1));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coords = vec2<i32>(global_id.xy);
    if (global_id.x >= dims.x || global_id.y >= dims.y) { return; }

    let uv = (vec2<f32>(coords) - 0.5 * vec2<f32>(dims)) / f32(dims.y);
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let rage = bass * 3.0;

    let mouse = (vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0) * vec2<f32>(f32(dims.x) / f32(dims.y), 1.0);
    let turnSpeed = u.zoom_params.x;
    let maxSpeed = u.zoom_params.y;
    let rageDuration = u.zoom_params.z;
    let glowRadius = u.zoom_params.w;

    let scalePattern = 4.0;
    var st = uv * scalePattern * 5.0;

    let baseDir = normalize(uv + vec2<f32>(0.001, 0.001));
    let targetDir = normalize(mouse - uv + vec2<f32>(0.001, 0.001));
    let dirToMouse = mix(baseDir, targetDir, turnSpeed);

    st += dirToMouse * time * maxSpeed;

    let voro = voronoi(st + vec2<f32>(time * 0.1, time * 0.15), time);
    let territoryBoundary = smoothstep(0.08, 0.0, voro.x);

    let id = floor(st);
    let f = fract(st) - 0.5;
    let rng = hash21(id);

    let raptorPos = f + dirToMouse * time * maxSpeed * 0.1;
    let scent = accumulateScent(uv, raptorPos, 0.5 + rage * 0.3);

    let gs = grayScottRD(uv * 2.0 + time * 0.1, 0.037, 0.06 + rage * 0.01);
    let rdEnergy = gs.x;

    let bodyRadius = 0.2 * (1.0 + rage * 0.5);
    let capsuleA = vec2<f32>(-0.15, 0.0);
    let capsuleB = vec2<f32>(0.15, 0.0);
    let capsuleDist = sdCapsule(f, capsuleA, capsuleB, bodyRadius * 0.6);

    let pursuit = pursuitVector(uv, mouse, maxSpeed);
    let chaseIntensity = smoothstep(0.5, 0.0, length(pursuit) * 0.1);
    let pursuitAngle = atan2(targetDir.y, targetDir.x);
    let preyField = sin(f.x * 6.0 + pursuitAngle) * cos(f.y * 6.0 - pursuitAngle) * 0.5 + 0.5;

    var territorialIntensity = 0.0;
    var energy = 0.0;
    var age = 0.0;
    var reproCooldown = 0.0;

    if (capsuleDist < 0.0) {
        territorialIntensity = 0.6 + rage * 0.4 + rng.x * 0.3 + preyField * 0.2 + chaseIntensity * 0.3;
        energy = 0.8 + scent * 0.5 + rdEnergy * 0.3 + chaseIntensity * 0.4;
        age = fract(time * 0.05 + rng.y * 10.0);
        reproCooldown = 1.0;
    } else {
        let glow = smoothstep(glowRadius * 0.6, 0.0, capsuleDist);
        let trailDecay = exp(-length(uv - mouse) * 2.0);
        territorialIntensity = territoryBoundary * 0.4 + glow * 0.2 + trailDecay * 0.1 + chaseIntensity * 0.15;
        energy = scent * 0.6 + rdEnergy * 0.4 + glow * 0.3 + chaseIntensity * 0.2;
        age = fract(length(uv) * 2.0 + time * 0.02);
        reproCooldown = glow * 0.35 + scent * 0.2 + trailDecay * 0.15;
    }

    var col = vec3<f32>(0.0);
    col.r = territorialIntensity * (0.8 + rage * 0.5);
    col.g = energy * 0.7 + scent * 0.4;
    col.b = age * 0.3 + rdEnergy * 0.15;
    let alpha = reproCooldown;

    let scaleTex = fract(length(f * rageDuration * 10.0));
    col *= 0.7 + 0.3 * scaleTex;

    textureStore(writeTexture, coords, vec4<f32>(col, alpha));

    let screenUv = (vec2<f32>(coords) + 0.5) / vec2<f32>(dims);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, screenUv, 0.0).r;
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
