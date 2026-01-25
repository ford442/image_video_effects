// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Scale, y=Distortion, z=Radius, w=Shadow
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    // Params
    let scale = 30.0 + u.zoom_params.x * 120.0; // Stitch density
    let pullStrength = u.zoom_params.y * 0.5;
    let pullRadius = u.zoom_params.z * 0.5;
    let depth = u.zoom_params.w;

    // Mouse Interaction: Pinch/Pull distortion
    let p = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(p);
    let pull = smoothstep(pullRadius, 0.0, dist) * pullStrength;

    // Distort UVs towards mouse (Pinch)
    // To make it look like pulling fabric, we shift UVs towards the center
    uv -= normalize(p) * pull * 0.2 * (1.0 / aspect); // Scale correction

    // Knitting Logic
    var st = uv * scale;

    // Offset every other row for brick/knit pattern
    // We use floor(st.y) to identify row
    let row = floor(st.y);
    if (row % 2.0 != 0.0) {
        st.x += 0.5;
    }

    let cellId = floor(st);
    let local = fract(st);

    // Normalize local coords to -1 to 1
    let lx = local.x * 2.0 - 1.0;
    let ly = local.y * 2.0 - 1.0;

    // Define the yarn shape (approximate)
    // A simple V shape or loop: y = x^2
    // We want the yarn to look round (tube).
    // Distance to the curve.

    // Curve 1: The main loop
    let curveY = lx * lx * 0.8 - 0.2;
    let d1 = abs(ly - curveY);

    // Curve 2: The loop underneath (for depth)
    let d2 = abs(ly - (curveY + 1.2)); // Roughly

    // Combine to get a "distance to yarn center"
    let d = min(d1, d2);

    // Create a height map / shading
    // Yarn is convex. 1.0 at center, 0.0 at edges.
    let yarnWidth = 0.35;
    let height = smoothstep(yarnWidth, 0.0, d);

    // Add some fiber noise
    let noise = sin(lx * 20.0 + ly * 30.0) * 0.1;

    // Final shading value
    let shading = height + noise;

    // Shadow between stitches (where height is low)
    let shadowVal = smoothstep(0.1, 0.4, height);

    // Sample Image
    // To make it look knitted, sample the average color of the cell
    // We transform cellId back to UV space
    var cellUV = cellId / scale;
    // Undo the row offset for correct sampling?
    // Actually cellId includes the offset x, so dividing by scale gives correct position roughly.
    // But we need to be careful about the row shift.
    // st.x was shifted. So cellId.x is shifted.
    if (row % 2.0 != 0.0) {
        cellUV.x -= 0.5 / scale;
    }

    // Sample
    let color = textureSampleLevel(readTexture, u_sampler, cellUV, 0.0).rgb;

    // Apply lighting
    // Mix shadow and highlight
    // Basic diffuse lighting:
    var finalColor = color * shadowVal;

    // Add specular highlight on the yarn
    let specular = smoothstep(0.8, 1.0, height) * 0.2 * depth;
    finalColor += specular;

    // Apply overall depth darkening
    finalColor = mix(finalColor, finalColor * shading, depth);

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));
}
