// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Growth buffer
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // Normal buffer
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,              // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,         // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,         // x=Scale, y=PopStrength, z=Refraction, w=Highlight
  ripples: array<vec4<f32>, 50>,
};

@group(0) @binding(3) var<uniform> u: Uniforms;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Read previous state (Channel R = Popped state 0.0 to 1.0)
    let oldState = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;

    // Params
    let bubblesScale = max(0.01, u.zoom_params.x * 0.1); // Scale
    let popStrength = u.zoom_params.y; // How visible the pop is (flattening)
    let refraction = u.zoom_params.z * 0.2; // Refraction strength
    let highlight = u.zoom_params.w * 0.8; // Specular highlight intensity

    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5;

    // Grid Logic
    let gridID = floor(uv / bubblesScale);
    let gridCenter = (gridID + 0.5) * bubblesScale;
    let localUV = (uv - gridID * bubblesScale) / bubblesScale; // 0 to 1

    // Mouse Interaction
    // Check distance from mouse to the CENTER of the bubble
    let dCenter = distance(gridCenter * vec2<f32>(aspect, 1.0), mousePos * vec2<f32>(aspect, 1.0));

    // If mouse is down and we are hovering over this bubble's center (approx), pop it
    // Radius of bubble in screen space is bubblesScale * 0.5 approx (ignoring aspect)
    // Let's use a fixed interactive radius or proportional to scale
    let interactRadius = bubblesScale * 0.8;

    var newState = oldState;
    if (mouseDown && dCenter < interactRadius) {
        newState = 1.0;
    }

    // Store State
    textureStore(dataTextureA, global_id.xy, vec4<f32>(newState, 0.0, 0.0, 1.0));

    // Rendering
    // SDF for circle
    let d = length(localUV - 0.5) * 2.0; // 0 at center, 1 at edge

    // Height/Normal
    // Sphere profile: z = sqrt(1 - d^2)
    var z = sqrt(max(0.0, 1.0 - d*d));

    // Apply Pop State
    // If popped, we flatten the bubble significantly
    let flattening = mix(1.0, 0.1, newState * popStrength);
    z = z * flattening;

    // Calculate Normal
    // Gradient of sphere height
    // n.xy ~ -gradient of z
    let normal = normalize(vec3<f32>((localUV - 0.5) * flattening, z));

    // Refraction
    // Sample texture with offset
    let refractUV = uv - normal.xy * refraction * z;

    var imgColor = textureSampleLevel(readTexture, u_sampler, refractUV, 0.0).rgb;

    // If popped, maybe darken or desaturate slightly to show it's "used"
    if (newState > 0.5) {
        imgColor = imgColor * 0.9;
    }

    // Specular Highlight
    // Simple Blinn-Phongish
    let lightDir = normalize(vec3<f32>(-0.5, -0.5, 1.0));
    let spec = pow(max(0.0, dot(normal, lightDir)), 20.0) * highlight;

    // Edges between bubbles
    let edge = smoothstep(0.85, 0.95, d);

    var finalColor = imgColor + spec;
    finalColor = mix(finalColor, vec3<f32>(0.05, 0.05, 0.05), edge); // Dark borders

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
