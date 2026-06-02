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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Read previous state (R = popped flag, G = time the pop happened)
    let oldData = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).rg;
    let oldState = oldData.r;
    let oldPopTime = oldData.g;
    let time = u.config.x;

    // Params
    let bubblesScale = max(0.01, u.zoom_params.x * 0.1); // Scale
    let popStrength = u.zoom_params.y; // How visible the pop is (flattening)
    let refraction = u.zoom_params.z * 0.2; // Refraction strength
    let highlight = u.zoom_params.w * 0.8; // Specular highlight intensity

    var mousePos = u.zoom_config.yz;
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

    // ═══ UNIQUE VISUAL IDEA: record the pop moment for an animated burst ═══
    var newState = oldState;
    var popTime = oldPopTime;
    if (mouseDown && dCenter < interactRadius && oldState < 0.5) {
        newState = 1.0;
        popTime = time; // stamp the instant of the pop so we can animate it
    }

    // Store State (R = popped, G = pop timestamp)
    textureStore(dataTextureA, global_id.xy, vec4<f32>(newState, popTime, 0.0, 1.0));

    // Age since this bubble popped (only meaningful once popped).
    let agePop = time - popTime;

    // Rendering
    // SDF for circle
    let d = length(localUV - 0.5) * 2.0; // 0 at center, 1 at edge

    // Height/Normal
    // Sphere profile: z = sqrt(1 - d^2)
    var z = sqrt(max(0.0, 1.0 - d*d));

    // Apply Pop State — animated elastic collapse instead of an instant flatten.
    // The membrane deflates over ~0.18s with a damped jiggle (rubbery snap-back).
    let collapseT = smoothstep(0.0, 0.18, agePop);
    let jiggle = sin(agePop * 42.0) * exp(-agePop * 9.0) * 0.18;
    let poppedFlatten = clamp(mix(1.0, 0.12, collapseT) + jiggle, 0.05, 1.0);
    let flattening = select(1.0, mix(1.0, poppedFlatten, popStrength), newState > 0.5);
    z = z * flattening;

    // Wrinkled deflated film: a popped bubble is a crinkled collapsed membrane, not
    // a smooth dome. Add high-frequency creases to its surface once collapsed.
    if (newState > 0.5) {
        let wr = sin(localUV.x * 60.0 + gridID.x) * sin(localUV.y * 60.0 + gridID.y);
        z = z + wr * 0.04 * collapseT;
    }

    // Calculate Normal
    let normal = normalize(vec3<f32>((localUV - 0.5) * flattening, z));

    // Refraction
    let refractUV = uv - normal.xy * refraction * z;

    var imgColor = textureSampleLevel(readTexture, u_sampler, refractUV, 0.0).rgb;

    // If popped, darken slightly to show it's "used"
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

    // Pop burst: a bright air-ring races outward from the bubble center in the
    // first moments after popping, then fades — the satisfying visual "snap".
    if (newState > 0.5 && agePop < 0.5) {
        let ringR = agePop * 5.0;            // expanding radius (in local 0..1 units)
        let ring = exp(-pow((d - ringR) * 5.0, 2.0)) * exp(-agePop * 7.0);
        finalColor = finalColor + vec3<f32>(0.9, 0.95, 1.0) * ring * 1.2;
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
