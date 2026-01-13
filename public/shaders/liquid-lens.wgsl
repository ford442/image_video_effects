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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;

    // Params
    let strength = u.zoom_params.x; // Refraction Strength
    let radius = u.zoom_params.y;   // Lens Radius
    let abberation = u.zoom_params.z; // Chromatic Abberation
    let edgeDarken = u.zoom_params.w; // Vignette/Edge darken of lens

    // Calculate distance to mouse
    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);
    let dist = distance(uvCorrected, mouseCorrected);

    // Lens profile (spherical)
    // 1.0 at center, 0.0 at radius
    let lensMask = smoothstep(radius, radius * 0.8, dist); // Inside lens

    // Calculate normal-ish offset
    // As we move away from center, we distort more? Or standard magnifying glass?
    // Magnifying glass: sample coordinates closer to center.
    // offset = (uv - mouse) * factor.

    // Sphere height estimation
    let h = sqrt(max(0.0, radius*radius - dist*dist));
    // Refraction depends on gradient of h.
    // Normalized distance
    let nd = dist / radius;
    // Simple distortion curve
    let distortion = pow(nd, 2.0) * strength * 0.5 * (1.0 - smoothstep(radius*0.9, radius, dist));

    let dir = normalize(uv - mouse);
    // Magnify: pull sample towards center
    // offset = -dir * distortion

    let baseOffset = -dir * distortion * lensMask;

    // Chromatic Abberation
    let ca = abberation * 0.02 * lensMask * nd; // More aberration at edges of lens

    let uvR = uv + baseOffset * (1.0 + ca);
    let uvG = uv + baseOffset;
    let uvB = uv + baseOffset * (1.0 - ca);

    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    var color = vec3<f32>(r, g, b);

    // Edge Darkening (simulate rim)
    let rim = smoothstep(radius * 0.8, radius, dist);
    if (dist < radius) {
        color = color * (1.0 - rim * edgeDarken);
        // Add a fake specular highlight?
        // Simple dot product with a "light source"
        let lightDir = normalize(vec2<f32>(-0.5, -0.5));
        // Surface normal estimation
        // sphere normal z is h/radius. xy is (uv-mouse)/radius
        let N = vec3<f32>((uvCorrected - mouseCorrected)/radius, h/radius);
        // This is rough but okay
        let spec = pow(max(0.0, dot(normalize(N), vec3<f32>(0.0, 0.0, 1.0) + vec3<f32>(-0.2, -0.2, 0.5))), 20.0);
        color += spec * 0.2;
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
}
