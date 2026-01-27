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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash(p: vec2<f32>) -> vec2<f32> {
    var p2 = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p2) * 43758.5453123);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    return mix(mix(dot(hash(i + vec2<f32>(0.0, 0.0)), f - vec2<f32>(0.0, 0.0)),
                   dot(hash(i + vec2<f32>(1.0, 0.0)), f - vec2<f32>(1.0, 0.0)), u.x),
               mix(dot(hash(i + vec2<f32>(0.0, 1.0)), f - vec2<f32>(0.0, 1.0)),
                   dot(hash(i + vec2<f32>(1.0, 1.0)), f - vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(uv: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var p = uv;
    for (var i = 0; i < octaves; i = i + 1) {
        value = value + amplitude * noise(p);
        p = p * 2.0;
        amplitude = amplitude * 0.5;
    }
    return value;
}

fn iridescence(t: f32) -> vec3<f32> {
    // Palette based on cosine
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.00, 0.33, 0.67);
    return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Params
    let speed = u.zoom_params.x * 2.0;
    let scale = u.zoom_params.y * 5.0 + 1.0;
    let strength = u.zoom_params.z;
    let refractStr = u.zoom_params.w * 0.1;
    let time = u.config.x * speed;
    let mouse = u.zoom_config.yz;

    // Mouse Interaction
    let mouse_vec = uv - mouse;
    let dist = length(mouse_vec * vec2<f32>(aspect, 1.0));
    let mouse_influence = smoothstep(0.4, 0.0, dist) * 2.0;

    // Coordinate distortion by mouse
    let dir = normalize(mouse_vec + vec2<f32>(0.001));
    var p = uv * scale;
    // Animate flow
    p.x = p.x + time * 0.1;
    p.y = p.y + time * 0.05;

    // Apply mouse stir
    p = p - dir * mouse_influence;

    let h = fbm(p, 5);

    // Normal calculation
    let eps = 0.01;
    let dx = fbm(p + vec2<f32>(eps, 0.0), 4) - h;
    let dy = fbm(p + vec2<f32>(0.0, eps), 4) - h;
    let n = normalize(vec3<f32>(-dx * 50.0, -dy * 50.0, 1.0));

    // Distorted UV for texture sample (refraction)
    let uv_new = uv + n.xy * refractStr;
    var color = textureSampleLevel(readTexture, u_sampler, uv_new, 0.0);

    // Iridescence color
    let thickness = h * 3.0 + time * 0.2 + dist * 0.5; // Rings around mouse too
    let iridColor = iridescence(thickness);

    // Specular
    let lightDir = normalize(vec3<f32>(-0.5, -0.5, 1.0));
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let halfVec = normalize(lightDir + viewDir);
    let spec = pow(max(dot(n, halfVec), 0.0), 32.0);

    // Blend
    // Overlay mode approximation
    let mixFactor = strength * (0.3 + spec * 0.7);
    color = mix(color, vec4<f32>(iridColor, 1.0), mixFactor);
    color = color + vec4<f32>(spec);

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);
}
