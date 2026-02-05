// --- PLASTIC BRICKS ---
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
  zoom_params: vec4<f32>,
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

    // Params
    let bricksAcross = mix(20.0, 100.0, u.zoom_params.x); // Brick Density
    let studSize = u.zoom_params.y * 0.4 + 0.1; // Stud Radius relative to cell
    let relief = u.zoom_params.z * 0.5; // Stud Height / Shadow intensity
    let bevel = u.zoom_params.w; // Brick bevel

    // Mouse Interaction: Local zoom or distorion?
    // Let's make mouse push the bricks slightly or change scale locally
    let mouse = u.zoom_config.yz;
    let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));

    // Scale bricks near mouse
    let scaleFactor = 1.0 + smoothstep(0.3, 0.0, dist) * 0.5;
    let density = bricksAcross / scaleFactor;

    // Grid coordinates
    let st = uv * vec2<f32>(aspect, 1.0) * density;
    let id = floor(st);
    let cell_uv = fract(st);

    // Center of cell
    let center = vec2<f32>(0.5);
    let d = distance(cell_uv, center);

    // Sample color from center of cell
    // Map back to UV
    let sample_uv = (id + 0.5) / density / vec2<f32>(aspect, 1.0);
    var color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0).rgb;

    // Stud drawing
    // Stud is a circle with highlight top-left, shadow bottom-right
    let studR = studSize;

    if (d < studR) {
        // Stud Top
        // Flat color, maybe slightly brighter
        color = color * (1.0 + relief * 0.1);

        // Specular highlight on stud
        let studLight = normalize(vec2<f32>(-1.0, -1.0));
        let p = (cell_uv - center) / studR; // -1 to 1
        // Fake spherical normal?
        // Or just flat cylinder with edge bevel

        // Simple cylinder rim
        if (d > studR * 0.8) {
            // bevel
            let angle = atan2(cell_uv.y - 0.5, cell_uv.x - 0.5);
            let light = cos(angle + 2.35); // 135 degrees
            color += vec3<f32>(light * relief);
        }
    } else {
        // Floor of the brick
        // Add shadow from the stud?
        // Shadow is offset to bottom right
        let shadowOffset = vec2<f32>(0.05, 0.05) * relief;
        let shadowDist = distance(cell_uv - shadowOffset, center);
        if (shadowDist < studR) {
            color *= 0.7;
        }
    }

    // Brick Bevel (edges of cell)
    let edgeX = min(cell_uv.x, 1.0 - cell_uv.x);
    let edgeY = min(cell_uv.y, 1.0 - cell_uv.y);
    let edge = min(edgeX, edgeY);

    if (edge < 0.05) {
        // Bevel logic
        // Top/Left = Light, Bottom/Right = Dark
        let isLight = (cell_uv.x < 0.05 || cell_uv.y < 0.05);
        if (isLight) {
            color += vec3<f32>(0.2 * relief);
        } else {
            color -= vec3<f32>(0.2 * relief);
        }
    }

    // Gap between bricks
    if (edge < 0.02) {
        color *= 0.5;
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
