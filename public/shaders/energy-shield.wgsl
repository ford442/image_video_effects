// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4 (Use these for ANY float sliders)
  ripples: array<vec4<f32>, 50>,
};

// Hexagon distance function
fn hexDist(p: vec2<f32>) -> f32 {
    let p_abs = abs(p);
    return max(p_abs.x, p_abs.x * 0.5 + p_abs.y * 0.866025);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Params
    let hexScale = 5.0 + u.zoom_params.x * 45.0; // 5 to 50
    let rippleSpeed = u.zoom_params.y * 5.0;
    let impactStrength = u.zoom_params.z;
    let decay = u.zoom_params.w;

    // Hex Grid UVs
    // Simple skewed grid for hex
    let r = vec2<f32>(1.0, 1.73);
    let h = r * 0.5;

    // Scale UV
    let scaledUV = uv * hexScale;
    scaledUV.x = scaledUV.x * aspect; // Correct aspect for grid

    let a = modulo(scaledUV, r) - h;
    let b = modulo(scaledUV - h, r) - h;

    let gv = dot(a, a) < dot(b, b) ? a : b;

    // Hex ID (approximate center)
    let hexCenter = scaledUV - gv;
    // Normalize back to 0-1 range for distance check
    let hexCenterUV = hexCenter / hexScale;
    hexCenterUV.x = hexCenterUV.x / aspect;

    // Mouse Interaction
    let mousePos = u.zoom_config.yz;
    let distVec = (hexCenterUV - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Ripple Effect
    // Time - Distance
    let wave = sin(dist * 20.0 - u.config.x * rippleSpeed);

    // Highlight based on mouse distance
    // Intensity drops off with distance
    let mouseIntensity = smoothstep(0.4, 0.0, dist);

    // Combine wave and mouse
    let activeHex = mouseIntensity + wave * 0.2 * impactStrength;

    // Hex Edges
    let hexD = hexDist(gv);
    let edge = smoothstep(0.48, 0.5, hexD); // 0 at center, 1 at edge
    let glow = smoothstep(0.4, 0.5, hexD) * activeHex;

    // Distort UV based on active hex
    let distortAmt = activeHex * 0.05 * impactStrength;
    let distortedUV = uv + (gv / hexScale) * distortAmt;

    let color = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0).rgb;

    // Add Hex Overlay
    // Colorize the edge
    let gridColor = vec3<f32>(0.0, 0.8, 1.0); // Cyan

    var finalColor = mix(color, gridColor, glow * 0.8);

    // Add extra brightness at the impact point
    finalColor = finalColor + gridColor * mouseIntensity * 0.2;

    // Use persistence to leave a trail?
    // Let's read history for a fading trail of activation
    // Coordinate for history needs to be uv
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).r;

    // Current activation
    let activation = mouseIntensity;

    // Accumulate
    let newTrail = max(prev * decay, activation);

    // Add trail to visual
    finalColor = finalColor + vec3<f32>(0.0, 0.5, 1.0) * newTrail * 0.5;

    // Store trail
    textureStore(dataTextureA, global_id.xy, vec4<f32>(newTrail, 0.0, 0.0, 1.0));

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));
}

fn modulo(x: vec2<f32>, y: vec2<f32>) -> vec2<f32> {
    return x - y * floor(x / y);
}
