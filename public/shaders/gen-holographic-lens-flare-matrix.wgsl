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

struct Uniforms { config: vec4<f32>, zoom_config: vec4<f32>, zoom_params: vec4<f32>, ripples: array<vec4<f32>, 50>; };

// hash function to get a random vec2 based on a vec2 seed
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + vec3<f32>(dot(p3, p3.yzx + vec3<f32>(33.33)));
    return fract((p3.xx + p3.yz) * p3.zy);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) GlobalInvocationID: vec3<u32>) {
    let coords = vec2<i32>(GlobalInvocationID.xy);
    let res = textureDimensions(writeTexture);

    if (coords.x >= i32(res.x) || coords.y >= i32(res.y)) { return; }

    let uv = vec2<f32>(coords) / vec2<f32>(res);
    let aspect = f32(res.x) / f32(res.y);
    let p = (uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);

    var col = vec3<f32>(0.0);
    let time = u.config.w;

    // Add mouse interaction via ripples
    var mouseOffset = vec2<f32>(0.0);
    for (var i = 0u; i < 50u; i = i + 1u) {
        let ripple = u.ripples[i];
        if (ripple.w > 0.0) {
            let rPos = ripple.xy;
            let d = length(p - rPos);
            // Influence the grid position based on mouse proximity
            mouseOffset = mouseOffset + normalize(p - rPos) * smoothstep(0.2, 0.0, d) * ripple.w;
        }
    }

    // gridSize is influenced by UI slider (zoom_params.x)
    let gridSize = 10.0 + u.zoom_params.x * 5.0;

    // Apply mouse displacement to grid UV
    let gUv = (p + mouseOffset * 0.1) * gridSize;
    let id = floor(gUv);
    let fUv = fract(gUv) - vec2<f32>(0.5);

    // Get random value for each cell
    let r = hash22(id);

    // Apply offset driven by zoom_config.y to push flares apart
    let offset = (r - vec2<f32>(0.5)) * u.zoom_config.y * 2.0;
    let flarePos = fUv - offset;
    let dist = length(flarePos);

    // Audio bass (u.config.x) influences size and spin speed
    let audioBass = u.config.x;
    let size = 0.1 + audioBass * 0.2;
    let spinSpeed = time * (1.0 + audioBass * 2.0);

    // Angle driven by time, audio, and UI sliders (zoom_params.w, zoom_config.z)
    let angle = atan2(flarePos.y, flarePos.x) + spinSpeed + u.zoom_params.w + u.zoom_config.z;

    // Compute density of flare with sine modulation for star-like shape
    var density = smoothstep(size, 0.0, dist);
    density = density * (0.5 + 0.5 * sin(angle * 4.0 + time * 5.0));

    // Write density to dataTextureA for soft-body blur step later
    textureStore(dataTextureA, coords, vec4<f32>(density, density, density, 1.0));

    // Color picking from plasmaBuffer using cell hash and time
    let plasmaIdx = u32(abs(fract(r.x + time * 0.1)) * f32(arrayLength(&plasmaBuffer)));
    var pColor = vec3<f32>(1.0);
    if (plasmaIdx < arrayLength(&plasmaBuffer)) {
        pColor = plasmaBuffer[plasmaIdx].rgb;
    }

    // Apply brightness slider
    let brightness = 1.0 + u.zoom_params.y;
    col = pColor * density * brightness;

    // Mix with motion/input texture
    let motion = textureLoad(readTexture, coords, 0).rgb;
    col = col + motion * 0.1;

    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
