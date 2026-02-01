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
  zoom_params: vec4<f32>,  // x=Density, y=Speed, z=Intensity, w=MouseInfl
  ripples: array<vec4<f32>, 50>,
};

// Helper: Random hash
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn hash12(p: vec2<f32>) -> f32 {
	var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    // Params
    let density = 3.0 + u.zoom_params.x * 5.0; // 3 to 8
    let speed = u.zoom_params.y;
    let intensity = u.zoom_params.z;
    let mouseInfl = u.zoom_params.w;

    let aspect = resolution.x / resolution.y;
    let uv_scaled = vec2<f32>(uv.x * aspect, uv.y) * density;

    let i_st = floor(uv_scaled);
    let f_st = fract(uv_scaled);

    var min_dist = 1.0;
    var min_point = vec2<f32>(0.0);
    var cell_id = vec2<f32>(0.0);

    // Voronoi Loop
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            var point = hash22(i_st + neighbor);

            // Animate point position slightly for organic feel
            point = 0.5 + 0.5 * sin(time * 0.5 + 6.2831 * point);

            let diff = neighbor + point - f_st;
            let dist = length(diff);

            if (dist < min_dist) {
                min_dist = dist;
                min_point = diff; // Vector from current pixel to center (actually center - pixel)
                // wait, diff = neighbor + point - f_st.
                // neighbor+point is Center position in grid space relative to i_st.
                // f_st is Pixel position in grid space relative to i_st.
                // so diff = Center - Pixel.
                cell_id = i_st + neighbor;
            }
        }
    }

    // Determine Zoom for this cell
    // Random base value per cell
    let randVal = hash12(cell_id);

    // Time varying component
    let cellTime = time * speed + randVal * 10.0;

    // Zoom oscillates.
    // Base scale 1.0. Variation +/- intensity.
    // Use sin/cos with different frequencies
    var zoomFactor = 1.0 + sin(cellTime) * 0.5 * intensity + cos(cellTime * 0.7) * 0.2 * intensity;

    // Mouse Influence
    let distMouse = distance(uv, mouse);

    // If mouseInfl is positive: proximity increases turbulence/zoom range
    // If negative: proximity stabilizes (sets zoom to 1.0)

    if (mouseInfl > 0.0) {
        let infl = smoothstep(0.5, 0.0, distMouse) * mouseInfl;
        zoomFactor += sin(time * 10.0 + randVal) * infl * 2.0;
    } else {
        let stab = smoothstep(0.5, 0.0, distMouse) * (-mouseInfl);
        zoomFactor = mix(zoomFactor, 1.0, stab);
    }

    // Apply Zoom
    // Center is current pixel + min_point (diff)
    // Pixel - Center = -diff

    let offsetFromCenter = -min_point;

    // We want to scale this offset.
    // newOffset = offset / zoom

    let shift = offsetFromCenter * (1.0 / max(0.1, zoomFactor) - 1.0);

    let uv_scaled_new = uv_scaled + shift;

    let uv_new = vec2<f32>(uv_scaled_new.x / aspect, uv_scaled_new.y) / density;

    // Sample
    // Handle wrapping manually if needed, or rely on sampler.
    // Let's add simple repeat just in case.
    let finalUV = fract(uv_new);

    var color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    textureStore(writeTexture, global_id.xy, color);

    // Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, finalUV, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
