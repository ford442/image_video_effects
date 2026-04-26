// ----------------------------------------------------------------
// Physarum (Slime Mold) Sacred Geometry
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=SensorAngle, y=SensorDist, z=DecayRate, w=DiffusionStrength
    ripples: array<vec4<f32>, 50>,
};

// Simple pseudo-random hash
fn hash(seed: u32) -> f32 {
    var x = seed;
    x ^= x >> 16u;
    x *= 0x7feb352du;
    x ^= x >> 15u;
    x *= 0x846ca68bu;
    x ^= x >> 16u;
    return f32(x) / f32(0xffffffffu);
}

// Get the trail density from a coordinate
fn sense(pos: vec2<f32>, angleOffset: f32, sensorDist: f32) -> f32 {
    let angle = angleOffset;
    let dir = vec2<f32>(cos(angle), sin(angle));
    let sensorPos = pos + dir * sensorDist;
    let texCoord = vec2<i32>(sensorPos);

    if (texCoord.x < 0 || texCoord.y < 0 || texCoord.x >= i32(u.config.z) || texCoord.y >= i32(u.config.w)) {
        return 0.0;
    }

    // Read the chemo-attractant
    let trail = textureLoad(dataTextureC, texCoord, 0).r;

    // Read the food/nutrient (video texture)
    let uv = sensorPos / vec2<f32>(u.config.z, u.config.w);
    let foodColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let food = (foodColor.r + foodColor.g + foodColor.b) * 0.333;

    return trail + food * 2.0; // Food has a stronger pull
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let res = vec2<i32>(u.config.z, u.config.w);

    if (coords.x >= res.x || coords.y >= res.y) {
        return;
    }

    let numAgents = res.x * res.y; // Every pixel corresponds to an agent slot
    let agentIdx = u32(coords.y * res.x + coords.x);

    // Init agents if state is 0
    if (extraBuffer[agentIdx * 4u + 3u] == 0.0) {
        extraBuffer[agentIdx * 4u + 0u] = hash(agentIdx * 3u) * f32(res.x);
        extraBuffer[agentIdx * 4u + 1u] = hash(agentIdx * 3u + 1u) * f32(res.y);
        extraBuffer[agentIdx * 4u + 2u] = hash(agentIdx * 3u + 2u) * 3.14159 * 2.0;
        extraBuffer[agentIdx * 4u + 3u] = 1.0; // Alive
    }

    var pos = vec2<f32>(extraBuffer[agentIdx * 4u + 0u], extraBuffer[agentIdx * 4u + 1u]);
    var angle = extraBuffer[agentIdx * 4u + 2u];

    let sensorAngle = u.zoom_params.x; // Default 0.5
    let sensorDist = u.zoom_params.y;  // Default 10.0

    let weightForward = sense(pos, angle, sensorDist);
    let weightLeft = sense(pos, angle + sensorAngle, sensorDist);
    let weightRight = sense(pos, angle - sensorAngle, sensorDist);

    let turnSpeed = 0.5 + u.config.y * 2.0; // Audio reacts here

    // Steering logic
    if (weightForward > weightLeft && weightForward > weightRight) {
        // Keep going straight
    } else if (weightForward < weightLeft && weightForward < weightRight) {
        // Turn randomly
        if (hash(agentIdx * 4u + u32(u.config.x * 1000.0)) > 0.5) {
            angle += turnSpeed * sensorAngle;
        } else {
            angle -= turnSpeed * sensorAngle;
        }
    } else if (weightLeft > weightRight) {
        angle += turnSpeed * sensorAngle;
    } else if (weightRight > weightLeft) {
        angle -= turnSpeed * sensorAngle;
    }

    // Mouse repulsion
    let mousePos = u.zoom_config.yz * vec2<f32>(u.config.z, u.config.w);
    let distToMouse = distance(pos, mousePos);
    if (distToMouse < 100.0) {
        let dirToMouse = normalize(mousePos - pos);
        let desiredAngle = atan2(-dirToMouse.y, -dirToMouse.x);
        angle = desiredAngle;
    }

    // Move agent
    let moveSpeed = 1.5;
    let dir = vec2<f32>(cos(angle), sin(angle));
    pos += dir * moveSpeed;

    // Bounds wrap
    if (pos.x < 0.0) { pos.x += f32(res.x); }
    if (pos.x >= f32(res.x)) { pos.x -= f32(res.x); }
    if (pos.y < 0.0) { pos.y += f32(res.y); }
    if (pos.y >= f32(res.y)) { pos.y -= f32(res.y); }

    // Save state
    extraBuffer[agentIdx * 4u + 0u] = pos.x;
    extraBuffer[agentIdx * 4u + 1u] = pos.y;
    extraBuffer[agentIdx * 4u + 2u] = angle;

    // Blur & Decay (executed for every pixel independently)
    var sum = 0.0;
    var count = 0.0;
    for (var i = -1; i <= 1; i++) {
        for (var j = -1; j <= 1; j++) {
            let offset = vec2<i32>(i, j);
            let nCoord = coords + offset;
            if (nCoord.x >= 0 && nCoord.y >= 0 && nCoord.x < res.x && nCoord.y < res.y) {
                sum += textureLoad(dataTextureC, nCoord, 0).r;
                count += 1.0;
            }
        }
    }

    let blurResult = sum / count;
    let decayRate = u.zoom_params.z; // Default 0.95
    let diffused = blurResult * decayRate;

    // If there is an agent here, add pheromone
    var agentAdded = 0.0;
    if (i32(pos.x) == coords.x && i32(pos.y) == coords.y) {
        agentAdded = 0.5;
    }

    textureStore(dataTextureA, coords, vec4<f32>(clamp(diffused + agentAdded, 0.0, 1.0), 0.0, 0.0, 1.0));

    // Map to color procedurally
    let trailDensity = textureLoad(dataTextureC, coords, 0).r;
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    let t = trailDensity * 2.0;
    let colorVec = a + b * cos(6.28318 * (c * t + d));
    let color = vec4<f32>(colorVec, 1.0);

    // Combine with original video
    let uv = vec2<f32>(coords) / vec2<f32>(res);
    let vidColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    let finalColor = mix(vidColor, color, trailDensity);

    textureStore(writeTexture, coords, finalColor);
}
