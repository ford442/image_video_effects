// ----------------------------------------------------------------
// Physarum (Slime Mold) Sacred Geometry (upgraded)
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=SensorAngle, y=SensorDist, z=DecayRate, w=DiffusionStrength
    ripples: array<vec4<f32>, 50>,
};

fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(controlled, color.a);
}

// Hashing primitives
fn hash(seed: u32) -> f32 {
    var x = seed;
    x ^= x >> 16u;
    x *= 0x7feb352du;
    x ^= x >> 15u;
    x *= 0x846ca68bu;
    x ^= x >> 16u;
    return f32(x) / f32(0xffffffffu);
}
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0;
    var a = 0.5;
    var f = 1.0;
    for (var i = 0; i < oct; i = i + 1) {
        s += a * valueNoise(p * f);
        f *= 2.0;
        a *= 0.5;
    }
    return s;
}
fn domainWarp(p: vec2<f32>, t: f32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t), 3), fbm(p + vec2<f32>(5.2, 1.3), 3));
    return p + 0.25 * q;
}

// Curl noise steers agents along the FBM gradient
fn curlNoise(p: vec2<f32>, t: f32) -> vec2<f32> {
    let e = 0.5;
    let n0 = fbm(p + vec2<f32>(e, 0.0) + t, 4);
    let n1 = fbm(p - vec2<f32>(e, 0.0) + t, 4);
    let n2 = fbm(p + vec2<f32>(0.0, e) + t, 4);
    let n3 = fbm(p - vec2<f32>(0.0, e) + t, 4);
    return vec2<f32>(n3 - n2, n0 - n1) / (2.0 * e);
}

// Hexagonal SDF sacred-geometry mask
fn hexDist(p: vec2<f32>) -> f32 {
    let s = vec2<f32>(1.0, 1.7320508);
    let h = s * 0.5;
    let a = abs(p - s * floor((p + h) / s)) - h;
    return max(a.x, a.y);
}
fn sacredMask(uv: vec2<f32>, t: f32) -> f32 {
    let h1 = smoothstep(0.06, 0.0, hexDist(uv * 12.0));
    let h2 = smoothstep(0.04, 0.0, hexDist(uv * 24.0 + vec2<f32>(t * 0.1)));
    return clamp(h1 + h2 * 0.5, 0.0, 1.0);
}

// Mandelbrot orbit trap for fractal color accents
fn mandelbrotTrap(c: vec2<f32>) -> f32 {
    var z = vec2<f32>(0.0);
    var trap = 100.0;
    for (var i = 0; i < 16; i = i + 1) {
        z = vec2<f32>(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
        trap = min(trap, length(z - vec2<f32>(0.3, 0.0)));
        if (dot(z, z) > 4.0) { break; }
    }
    return trap;
}

// Sense trail + domain-warped food + geometry aura (branchless bounds)
fn sense(pos: vec2<f32>, angleOffset: f32, sensorDist: f32) -> f32 {
    let angle = angleOffset;
    let dir = vec2<f32>(cos(angle), sin(angle));
    let sensorPos = pos + dir * sensorDist;
    let res = vec2<f32>(u.config.z, u.config.w);
    let inBounds = step(0.0, sensorPos.x) * step(sensorPos.x, res.x - 1.0) *
                   step(0.0, sensorPos.y) * step(sensorPos.y, res.y - 1.0);
    let clampedPos = clamp(sensorPos, vec2<f32>(0.0), res - 1.0);
    let trail = textureLoad(dataTextureC, vec2<i32>(clampedPos), 0).r;
    let uv = sensorPos / res;
    let warp = domainWarp(uv * 4.0, u.config.x * 0.1);
    let foodColor = textureSampleLevel(readTexture, u_sampler, clamp(warp, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let food = dot(foodColor, vec3<f32>(0.333));
    let geo = sacredMask(uv, u.config.x);
    return inBounds * (trail * (1.0 + geo * 0.5) + food * 2.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let res = vec2<i32>(i32(u.config.z), i32(u.config.w));
    if (coords.x >= res.x || coords.y >= res.y) { return; }

    let numAgents = res.x * res.y;
    let agentIdx = u32(coords.y * res.x + coords.x);
    let time = u.config.x;
    let audio = u.config.y;

    // Init agents if state is 0
    if (extraBuffer[agentIdx * 4u + 3u] == 0.0) {
        extraBuffer[agentIdx * 4u + 0u] = hash(agentIdx * 3u) * f32(res.x);
        extraBuffer[agentIdx * 4u + 1u] = hash(agentIdx * 3u + 1u) * f32(res.y);
        extraBuffer[agentIdx * 4u + 2u] = hash(agentIdx * 3u + 2u) * 3.14159 * 2.0;
        extraBuffer[agentIdx * 4u + 3u] = 1.0;
    }

    var pos = vec2<f32>(extraBuffer[agentIdx * 4u + 0u], extraBuffer[agentIdx * 4u + 1u]);
    var angle = extraBuffer[agentIdx * 4u + 2u];

    let sensorAngle = u.zoom_params.x;
    let sensorDist = u.zoom_params.y;
    let turnSpeed = 0.5 + plasmaBuffer[0].x * 2.0;

    // Curl-noise steering bias
    let curl = curlNoise(pos * 0.02, time * 0.2);
    angle += curl.x * 0.15 * (1.0 + audio);

    // Branchless sense weights
    let wF = sense(pos, angle, sensorDist);
    let wL = sense(pos, angle + sensorAngle, sensorDist);
    let wR = sense(pos, angle - sensorAngle, sensorDist);

    let randomDir = select(-1.0, 1.0, hash(agentIdx * 4u + u32(time * 1000.0)) > 0.5);
    let forwardWins = select(0.0, 1.0, wF >= wL && wF >= wR);
    let pinWheel = select(0.0, 1.0, wF < wL && wF < wR);
    let leftWins = select(0.0, 1.0, wL > wR);
    let rightWins = select(0.0, 1.0, wR > wL);
    let turn = (1.0 - forwardWins) * (
        pinWheel * randomDir * turnSpeed * sensorAngle +
        (1.0 - pinWheel) * (leftWins - rightWins) * turnSpeed * sensorAngle
    );
    angle += turn;

    // Branchless mouse repulsion
    let mousePos = u.zoom_config.yz * vec2<f32>(u.config.z, u.config.w);
    let distToMouse = distance(pos, mousePos);
    let dirToMouse = normalize(mousePos - pos);
    let desiredAngle = atan2(-dirToMouse.y, -dirToMouse.x);
    angle = mix(angle, desiredAngle, smoothstep(120.0, 80.0, distToMouse));

    // Move agent
    let moveSpeed = 1.5 + audio * 0.8;
    let dir = vec2<f32>(cos(angle), sin(angle));
    pos += dir * moveSpeed;

    // Branchless wrap-around bounds
    let fw = f32(res.x);
    let fh = f32(res.y);
    pos.x = select(pos.x + fw, pos.x, pos.x >= 0.0);
    pos.x = select(pos.x - fw, pos.x, pos.x < fw);
    pos.y = select(pos.y + fh, pos.y, pos.y >= 0.0);
    pos.y = select(pos.y - fh, pos.y, pos.y < fh);

    extraBuffer[agentIdx * 4u + 0u] = pos.x;
    extraBuffer[agentIdx * 4u + 1u] = pos.y;
    extraBuffer[agentIdx * 4u + 2u] = angle;

    // Blur & decay with branchless border weighting
    var sum = 0.0;
    var count = 0.0;
    for (var i = -1; i <= 1; i = i + 1) {
        for (var j = -1; j <= 1; j = j + 1) {
            let nCoord = coords + vec2<i32>(i, j);
            let inBounds = select(0.0, 1.0, nCoord.x >= 0 && nCoord.y >= 0 && nCoord.x < res.x && nCoord.y < res.y);
            let samplePos = clamp(nCoord, vec2<i32>(0), res - vec2<i32>(1));
            sum += inBounds * textureLoad(dataTextureC, samplePos, 0).r;
            count += inBounds;
        }
    }
    let blurResult = sum / max(count, 1.0);
    let decayRate = u.zoom_params.z;
    let diffused = blurResult * decayRate;

    // Branchless pheromone deposition when agent occupies this pixel
    let atPixel = select(0.0, 0.5, i32(pos.x) == coords.x && i32(pos.y) == coords.y);
    let geo = sacredMask(vec2<f32>(coords) / vec2<f32>(res), time);
    let deposited = clamp(diffused + atPixel * (1.0 + geo), 0.0, 1.0);
    textureStore(dataTextureA, coords, vec4<f32>(deposited, 0.0, 0.0, 1.0));

    // Procedural color mapping with geometry + orbit trap accents
    let trailDensity = textureLoad(dataTextureC, coords, 0).r;
    let trap = mandelbrotTrap((vec2<f32>(coords) / vec2<f32>(res) - 0.5) * 2.5);
    let accent = exp(-trap * 5.0) * (0.5 + audio);
    let t = trailDensity * 2.0 + geo * 0.6 + accent * 0.4;
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    let colorVec = a + b * cos(6.28318 * (c * t + d));
    let color = vec4<f32>(colorVec, 1.0);

    // Composite with original video
    let uv = vec2<f32>(coords) / vec2<f32>(res);
    let vidColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let alpha = clamp(trailDensity + geo * 0.4 + accent * 0.3, 0.0, 1.0);
    let finalColor = mix(vidColor, vec4<f32>(colorVec, alpha), trailDensity + geo * 0.25);

    // Depth-aware output
    let _depth_uv = clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0));
    let _depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, _depth_uv, 0.0).r;
    let outDepth = mix(_depth, 0.2 + trailDensity * 0.6, alpha);

    textureStore(writeTexture, coords, applyGenerativePrimaryControls(finalColor));
    textureStore(writeDepthTexture, coords, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
