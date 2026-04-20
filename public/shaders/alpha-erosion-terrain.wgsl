// ═══════════════════════════════════════════════════════════════════
//  Alpha Erosion Terrain
//  Category: simulation
//  Features: mouse-driven, temporal, rgba-state-machine
//  Complexity: High
//  RGBA Channels:
//    R = Terrain height (from image luminance, can change)
//    G = Water depth (0.0 to 1.0+)
//    B = Sediment carried by water (0.0 to 1.0)
//    A = Accumulated erosion amount (history of material removed)
//  Why f32: Hydraulic erosion requires tracking millimeter-scale
//  height changes over thousands of iterations. 8-bit would make
//  the terrain either flat or cliff with no gradual valleys.
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

@compute @workgroup_size(8, 8, 1)
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
    var water = prevState.g;
    var sediment = prevState.b;
    var erosion = prevState.a;

    // Seed on first frame from image luminance
    if (time < 0.1) {
        let sourceLuma = dot(textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
        height = sourceLuma;
        water = 0.0;
        sediment = 0.0;
        erosion = 0.0;
    }

    height = clamp(height, 0.0, 2.0);
    water = clamp(water, 0.0, 2.0);
    sediment = clamp(sediment, 0.0, 2.0);
    erosion = clamp(erosion, 0.0, 2.0);

    // === PARAMETERS ===
    let rainRate = mix(0.001, 0.01, u.zoom_params.x);
    let erosionRate = mix(0.01, 0.1, u.zoom_params.y);
    let depositionRate = mix(0.01, 0.1, u.zoom_params.z);

    // === NEIGHBOR SAMPLES ===
    let left = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let right = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let down = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let up = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    // === HEIGHT GRADIENT ===
    let gradX = (right.r - left.r) / (2.0 * ps.x);
    let gradY = (up.r - down.r) / (2.0 * ps.y);
    let slope = length(vec2<f32>(gradX, gradY));

    // === WATER FLOW ===
    // Water flows downhill
    let waterCapacity = slope * water * erosionRate;
    let sedimentExcess = sediment - waterCapacity;

    // Erode if carrying too little sediment
    if (sedimentExcess < 0.0 && water > 0.01) {
        let erodeAmount = min(-sedimentExcess * 0.1, height * 0.01);
        height -= erodeAmount;
        sediment += erodeAmount;
        erosion += erodeAmount;
    }
    // Deposit if carrying too much
    else if (sedimentExcess > 0.0) {
        let depositAmount = sedimentExcess * depositionRate;
        height += depositAmount;
        sediment -= depositAmount;
    }

    // === WATER MOVEMENT (advect toward lower neighbors) ===
    var flowOut = 0.0;
    let myTotalHeight = height + water * 0.1;
    let lTotal = left.r + left.g * 0.1;
    let rTotal = right.r + right.g * 0.1;
    let dTotal = down.r + down.g * 0.1;
    let uTotal = up.r + up.g * 0.1;

    flowOut += max(0.0, myTotalHeight - lTotal) * 0.1;
    flowOut += max(0.0, myTotalHeight - rTotal) * 0.1;
    flowOut += max(0.0, myTotalHeight - dTotal) * 0.1;
    flowOut += max(0.0, myTotalHeight - uTotal) * 0.1;

    water += rainRate;
    water -= flowOut;
    water = max(water, 0.0);

    // Sediment moves with water
    sediment *= 0.995; // Some sediment settles

    // === MOUSE RAIN ===
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseRain = smoothstep(0.15, 0.0, mouseDist) * mouseDown;
    water += mouseRain * 0.3;

    // === RIPPLE STORMS ===
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 0.5 && rDist < 0.08) {
            let storm = smoothstep(0.08, 0.0, rDist) * max(0.0, 1.0 - age * 2.0);
            water += storm * 0.2;
        }
    }

    water = clamp(water, 0.0, 2.0);
    height = clamp(height, 0.0, 2.0);
    sediment = clamp(sediment, 0.0, 2.0);

    // === STORE STATE ===
    textureStore(dataTextureA, coord, vec4<f32>(height, water, sediment, erosion));

    // === VISUALIZATION ===
    // Height = terrain color
    let lowColor = vec3<f32>(0.2, 0.15, 0.1);    // Deep brown
    let midColor = vec3<f32>(0.4, 0.35, 0.2);    // Earth
    let highColor = vec3<f32>(0.8, 0.8, 0.75);   // Stone/snow

    var terrainColor: vec3<f32>;
    if (height < 0.3) {
        terrainColor = mix(lowColor, midColor, height / 0.3);
    } else if (height < 0.7) {
        terrainColor = mix(midColor, highColor, (height - 0.3) / 0.4);
    } else {
        terrainColor = highColor;
    }

    // Water overlay
    let waterColor = vec3<f32>(0.2, 0.4, 0.6);
    let waterVis = min(water, 1.0);
    var displayColor = mix(terrainColor, waterColor, waterVis * 0.6);

    // Sediment = muddy brown tint
    let sedimentColor = vec3<f32>(0.5, 0.4, 0.2);
    displayColor = mix(displayColor, sedimentColor, min(sediment, 0.5));

    // Erosion = reddish scars
    let erosionColor = vec3<f32>(0.6, 0.3, 0.2);
    displayColor = mix(displayColor, erosionColor, min(erosion * 0.5, 0.3));

    displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, coord, vec4<f32>(displayColor, water));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
