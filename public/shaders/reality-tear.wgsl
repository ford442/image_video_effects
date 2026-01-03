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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Radius, y=Jaggedness, z=BorderWidth, w=StaticAmount
  ripples: array<vec4<f32>, 50>,
};

// --- Hash & Noise Functions ---
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn valueNoise2D(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);

    // Four corners
    let a = hash21(i + vec2<f32>(0.0, 0.0));
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));

    // Smooth interpolation
    let u = f * f * (3.0 - 2.0 * f);

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let time = u.config.x;
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Parameters
    let radiusBase = u.zoom_params.x * 0.5; // x: Tear Radius
    let jaggedness = u.zoom_params.y;      // y: Jaggedness
    let borderWidth = u.zoom_params.z * 0.05; // z: Border Width
    let staticAmt = u.zoom_params.w;       // w: Static/Void Amount

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let aspectRatio = resolution.x / resolution.y;

    // Correct for aspect ratio for distance calculation
    let uv_c = vec2<f32>(uv.x * aspectRatio, uv.y);
    let mouse_c = vec2<f32>(mouse.x * aspectRatio, mouse.y);

    let dist = distance(uv_c, mouse_c);
    let angle = atan2(uv_c.y - mouse_c.y, uv_c.x - mouse_c.x);

    // Calculate noisy radius for jagged edge
    // Use time to animate the tear slightly
    let noiseVal = valueNoise2D(vec2<f32>(angle * 3.0, time * 0.5)) * 0.5 +
                   valueNoise2D(vec2<f32>(angle * 10.0, time * 2.0)) * 0.5;

    let currentRadius = radiusBase + (noiseVal - 0.5) * jaggedness * radiusBase;

    var finalColor: vec3<f32>;

    if (dist < currentRadius) {
        // Inside the tear: "The Void"
        // Invert original colors or show static

        // Static noise
        let noise = hash21(uv * 100.0 + time);

        // Sample original but heavily distorted or inverted
        let distUV = uv + vec2<f32>(noise * 0.05);
        let tex = textureSampleLevel(readTexture, u_sampler, distUV, 0.0).rgb;

        let voidColor = vec3<f32>(noise * staticAmt); // Black/White static
        let inverted = vec3<f32>(1.0) - tex;

        finalColor = mix(inverted, voidColor, 0.5);

    } else if (dist < currentRadius + borderWidth) {
        // Border of the tear (Glowing/Burned edge)
        let borderFactor = (dist - currentRadius) / borderWidth; // 0.0 (inner) to 1.0 (outer)

        // Burning orange/red edge
        let burnColor = vec3<f32>(1.0, 0.4, 0.1) * 2.0;
        finalColor = mix(burnColor, textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb, borderFactor);

    } else {
        // Outside: Normal reality
        finalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));
}
