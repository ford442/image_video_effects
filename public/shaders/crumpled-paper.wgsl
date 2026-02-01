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
  config: vec4<f32>,       // x=Time
  zoom_config: vec4<f32>,  // y=MouseX, z=MouseY
  zoom_params: vec4<f32>,  // x=Scale, y=Depth, z=SmoothRadius, w=LightStrength
  ripples: array<vec4<f32>, 50>,
};

// --- Noise Functions ---

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

// 5-Octave FBM
fn fbm5(p: vec2<f32>) -> f32 {
    var sum = 0.0;
    var amp = 1.0;
    var freq = 1.0;
    var maxAmp = 0.0;

    for (var i: i32 = 0; i < 5; i = i + 1) {
        sum = sum + amp * valueNoise2D(p * freq);
        maxAmp = maxAmp + amp;
        freq = freq * 2.0;
        amp = amp * 0.5; // persistence
    }

    return sum / maxAmp;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz; // 0..1

    // Params
    let scale = mix(2.0, 10.0, u.zoom_params.x); // Crumple frequency
    let depth = u.zoom_params.y;                 // Crumple amplitude
    let smoothRadius = u.zoom_params.z * 0.5;    // Mouse ironing radius
    let lightStrength = u.zoom_params.w;

    // Calculate Height Map
    // We use FBM noise.
    let noiseVal = fbm5(uv * scale + vec2<f32>(12.3, 45.6));

    // Crumple Logic:
    // Crumpled paper has sharp creases. We can map the noise to create ridges.
    // 1.0 - abs(noise - 0.5) * 2.0 creates ridges.
    let ridge = pow(1.0 - abs(noiseVal - 0.5) * 2.0, 2.0);

    // Combine base noise and ridges
    var height = mix(noiseVal, ridge, 0.6) * depth;

    // Mouse Interaction (Smoothing/Ironing)
    // Distance to mouse
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    // Fix: smoothstep edges must be e0 < e1. We want 1.0 when dist=0, 0.0 when dist=radius.
    // Use 1.0 - smoothstep(0, radius, dist).
    // Ensure smoothRadius is > 0 to avoid undefined behavior.
    let sr = max(0.001, smoothRadius);
    let smoothFactor = 1.0 - smoothstep(0.0, sr, dist);

    // Reduce height where mouse is (flatten the paper)
    height = height * (1.0 - smoothFactor);

    // Calculate Normal
    // Since we don't have analytical derivative easily, we sample neighboring heights.
    // However, recalculating FBM 2 more times per pixel is expensive.
    // A cheaper way is to assume the derivative of noise is somewhat related to its value or use a cheaper noise for derivative.
    // But for quality, let's recalculate FBM for neighbors.
    // Wait, let's optimize: only 1 sample if we assume lighting comes from top-left constant?
    // No, we need normals for dynamic lighting.

    let eps = 0.005; // sampling step

    // Helper to get height at offset
    // (Inlined for simplicity or we define function but requires passing uniforms)
    // We just reuse logic approx.
    let nR = fbm5((uv + vec2<f32>(eps, 0.0)) * scale + vec2<f32>(12.3, 45.6));
    let rR = pow(1.0 - abs(nR - 0.5) * 2.0, 2.0);
    let hR = mix(nR, rR, 0.6) * depth;
    // Apply smoothing to neighbor too
    let distR = length(((uv + vec2<f32>(eps, 0.0)) - mouse) * vec2<f32>(aspect, 1.0));
    let smoothR = 1.0 - smoothstep(0.0, sr, distR);
    let finalHR = hR * (1.0 - smoothR);

    let nU = fbm5((uv + vec2<f32>(0.0, eps)) * scale + vec2<f32>(12.3, 45.6));
    let rU = pow(1.0 - abs(nU - 0.5) * 2.0, 2.0);
    let hU = mix(nU, rU, 0.6) * depth;
    let distU = length(((uv + vec2<f32>(0.0, eps)) - mouse) * vec2<f32>(aspect, 1.0));
    let smoothU = 1.0 - smoothstep(0.0, sr, distU);
    let finalHU = hU * (1.0 - smoothU);

    let dX = (finalHR - height) / eps;
    let dY = (finalHU - height) / eps;

    let normal = normalize(vec3<f32>(-dX, -dY, 1.0));

    // Lighting
    let lightDir = normalize(vec3<f32>(0.5, -0.5, 1.0)); // Top-right light
    let diffuse = max(dot(normal, lightDir), 0.0);

    // Ambient occlusion in creases (where height is low?)
    // Actually where ridge is sharp.
    // Let's just map height to ambient. Lower parts are darker.
    let ambient = 0.5 + 0.5 * height;

    let lighting = ambient * 0.5 + diffuse * 0.8;

    // Apply texture distortion
    // Refract texture based on normal xy
    let distortStr = 0.02 * depth;
    let finalUV = uv + normal.xy * distortStr;

    let texColor = textureSampleLevel(readTexture, u_sampler, clamp(finalUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;

    // Mix lighting
    // If lightStrength is 0, we see pure image. If 1, we see paper texture heavily applied.
    // Paper is usually white.
    // Let's multiply image by lighting (modulate).
    var finalColor = texColor * mix(1.0, lighting, lightStrength);

    // Add specular highlight for shiny paper?
    // Maybe paper is matte.

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

    let depthVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depthVal, 0.0, 0.0, 0.0));
}
