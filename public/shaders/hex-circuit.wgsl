// ────────────────────────────────────────────────────────────────────────────────
//  Hex Circuit – Cybernetic Grid Overlay
//  - Overlays a hexagonal grid that reacts to image edges and mouse pulses.
//  - High-tech, futuristic aesthetic.
// ────────────────────────────────────────────────────────────────────────────────

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
  config: vec4<f32>,       // x=Time
  zoom_config: vec4<f32>,  // y=MouseX, z=MouseY
  zoom_params: vec4<f32>,  // x=GridSize, y=Glow, z=PulseSpeed, w=EdgeSens
  ripples: array<vec4<f32>, 50>,
};

// Distance to hex edge
fn hexEdgeDist(p: vec2<f32>) -> f32 {
    var q = abs(p);
    return max(q.x * 0.5 + q.y * 0.866025, q.x); // Outer radius is 1.0
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = u.config.zw;
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / dims;
    let aspect = dims.x / dims.y;
    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);

    // Params
    let gridSize = mix(10.0, 50.0, u.zoom_params.x);
    let glowStrength = mix(0.5, 3.0, u.zoom_params.y);
    let pulseSpeed = u.zoom_params.z * 5.0;
    let edgeSens = u.zoom_params.w;

    let p = uvCorrected * gridSize;

    // Hex Grid Calculation
    // https://www.youtube.com/watch?v=VmrIDyYiJBA
    let r = vec2<f32>(1.0, 1.7320508);
    let h = r * 0.5;

    // Simplified logic removing modf
    let fractA = fract(p / r) * r - h;
    let fractB = (fract((p / r) + 0.5) * r) - h;

    // Determine which grid cell we are in
    var localUV = vec2<f32>(0.0);
    // var id = vec2<f32>(0.0); // ID unused for now

    if (dot(fractA, fractA) < dot(fractB, fractB)) {
        localUV = fractA;
        // id = floor(p / r);
    } else {
        localUV = fractB;
        // id = floor((p / r) + 0.5);
    }

    // Calculate distance to edge of hex
    var q = abs(localUV);
    let distToCenter = max(q.x * 0.5 + q.y * 0.866025, q.x); // This approximates distance
    let distToEdge = 0.5 - distToCenter;

    // Edge Detection from Image
    let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let texel = 1.0 / dims;
    let cR = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).rgb;
    let cU = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).rgb;

    let luma = dot(c, vec3<f32>(0.333));
    let lumaR = dot(cR, vec3<f32>(0.333));
    let lumaU = dot(cU, vec3<f32>(0.333));

    let imgEdge = sqrt(pow(luma - lumaR, 2.0) + pow(luma - lumaU, 2.0));

    // Mouse Pulse
    let mouse = u.zoom_config.yz;
    let mouseDist = distance(uvCorrected, vec2<f32>(mouse.x * aspect, mouse.y));
    let pulseTime = u.config.x * pulseSpeed;
    let wave = sin(mouseDist * 10.0 - pulseTime);
    let pulse = smoothstep(0.8, 1.0, wave); // Sharp wave ring

    // Final color logic
    var color = c * 0.7; // Dim background

    // Hex Lines
    let lineThickness = 0.02; // relative to grid
    // Fixed undefined smoothstep behavior (high < low)
    let isHexLine = 1.0 - smoothstep(0.0, lineThickness, distToEdge);

    // Determine glow color
    let hexColor = mix(vec3<f32>(0.0, 0.5, 1.0), vec3<f32>(1.0, 0.0, 0.5), pulse);

    // Light up hexes that contain image edges OR are hit by pulse
    let activeHex = step(edgeSens * 0.1, imgEdge) * 0.8 + pulse * 0.5;

    if (isHexLine > 0.0) {
        color = mix(color, hexColor * glowStrength, isHexLine * clamp(activeHex + 0.2, 0.2, 1.0));
    } else {
        // Fill hex slightly if active
        color += hexColor * activeHex * 0.2;
    }

    // Highlight near mouse
    // Fixed undefined smoothstep behavior
    let mouseHover = 1.0 - smoothstep(0.0, 0.2, mouseDist);
    color += mouseHover * vec3<f32>(0.1, 0.1, 0.2);

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
}
