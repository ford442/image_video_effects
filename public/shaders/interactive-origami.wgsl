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

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,  // x=FoldScale, y=FoldDepth, z=LightIntensity, w=Unused
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let aspectVec = vec2<f32>(aspect, 1.0);

    // Params
    let foldScale = mix(2.0, 20.0, u.zoom_params.x);
    let foldDepth = u.zoom_params.y * 0.05;
    let lightInt = u.zoom_params.z;

    let mouse = u.zoom_config.yz;
    let dist = distance((uv - mouse) * aspectVec, vec2<f32>(0.0));

    // Generate fold lines based on mouse position
    // We create a few sine waves oriented around the mouse

    let angle1 = 0.5;
    let angle2 = 2.1; // Different angle
    let angle3 = 4.0;

    // Normal vectors for the "fold lines"
    let n1 = vec2<f32>(cos(angle1), sin(angle1));
    let n2 = vec2<f32>(cos(angle2), sin(angle2));
    let n3 = vec2<f32>(cos(angle3), sin(angle3));

    // Distance from pixel to line passing through mouse
    let d1 = dot((uv - mouse) * aspectVec, n1);
    let d2 = dot((uv - mouse) * aspectVec, n2);
    let d3 = dot((uv - mouse) * aspectVec, n3);

    // Create sharp creases using abs(sin) or triangle wave
    // Triangle wave: 2 * abs(fract(x) - 0.5)

    let wave1 = abs(sin(d1 * foldScale));
    let wave2 = abs(sin(d2 * foldScale * 0.7)); // Different freq
    let wave3 = abs(sin(d3 * foldScale * 1.3));

    // Combined height map
    let height = wave1 + wave2 + wave3;

    // Gradient of height for displacement (normal-ish)
    // Approximate derivative
    let delta = 0.01;
    let h_right = abs(sin((d1 + delta) * foldScale)) + abs(sin((d2 + delta) * foldScale * 0.7)) + abs(sin((d3 + delta) * foldScale * 1.3));
    let h_up = abs(sin(dot(((uv + vec2<f32>(0.0, delta)) - mouse) * aspectVec, n1) * foldScale)) +
               abs(sin(dot(((uv + vec2<f32>(0.0, delta)) - mouse) * aspectVec, n2) * foldScale * 0.7)) +
               abs(sin(dot(((uv + vec2<f32>(0.0, delta)) - mouse) * aspectVec, n3) * foldScale * 1.3));

    let grad = vec2<f32>(h_right - height, h_up - height) / delta;

    // Displace UVs
    // Influence falls off away from mouse
    let influence = smoothstep(0.8, 0.0, dist);
    let finalUV = uv - grad * foldDepth * influence;

    let col = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    // Lighting
    // Use the gradient to simulate light hitting the folds
    // Light direction is from top-left
    let lightDir = normalize(vec2<f32>(-1.0, -1.0));
    let diffuse = dot(normalize(grad), lightDir);

    // Add specular highlight on ridges
    let ridge = pow(height / 3.0, 4.0); // sharp peaks

    let lighting = (diffuse * 0.5 + ridge) * lightInt * influence;

    let finalColor = col + vec4<f32>(lighting, lighting, lighting, 0.0);

    textureStore(writeTexture, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
}
