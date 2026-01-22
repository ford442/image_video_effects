@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;
@group(0) @binding(7) var feedbackOut: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var normalBuf:   texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var feedbackTex: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config:      vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples:     array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    let uv = vec2<f32>(gid.xy) / dims;
    let aspect = dims.x / dims.y;
    let mouse = u.zoom_config.yz; // Mouse coordinates (0..1)
    let time = u.config.x;

    // Grid configuration
    let gridSize = 20.0; // Number of bricks across Y
    let scale = vec2<f32>(gridSize * aspect, gridSize);

    let cellID = floor(uv * scale);
    let cellUV = fract(uv * scale); // 0..1 inside the cell

    // Cell Center in UV space
    let cellCenter = (cellID + 0.5) / scale;

    // Interaction Vector
    // Fix aspect ratio for distance calculation
    let aspectVec = vec2<f32>(aspect, 1.0);
    let vecToMouse = (mouse - cellCenter) * aspectVec;
    let dist = length(vecToMouse);

    // Interaction Strength (Radius)
    let radius = 0.5;
    let influence = smoothstep(radius, 0.0, dist);

    // Calculate simulated normal
    // Base normal is Z-up (0,0,1). Mouse tilts it.
    // We tilt the "brick" towards the mouse (or away).
    // Let's make it tilt towards the mouse as if pressed down at the mouse position.

    var tilt = vec2<f32>(0.0);
    if (dist > 0.001) {
        tilt = normalize(vecToMouse) * influence;
    }

    // Refraction Offset
    // Bevel edges of the brick for 3D look
    let bevelX = smoothstep(0.0, 0.1, cellUV.x) * (1.0 - smoothstep(0.9, 1.0, cellUV.x));
    let bevelY = smoothstep(0.0, 0.1, cellUV.y) * (1.0 - smoothstep(0.9, 1.0, cellUV.y));
    let bevel = bevelX * bevelY;

    // Determine displacement
    // Displacement logic: we sample the texture at a different location.
    // If the glass is tilted, the ray bends.
    // Simple 2D approx: offset UV by the tilt vector.
    let refractionStrength = 0.05;
    let offset = tilt * refractionStrength;

    // Add slight bevel distortion to make it look like thick glass
    let bevelDistort = (vec2<f32>(0.5) - cellUV) * 0.02 * (1.0 - bevel);

    let finalUV = uv + offset + bevelDistort;

    // Chromatic Aberration (Dispersion)
    let caStrength = 0.01 * influence + 0.005; // More CA when tilted

    let r = textureSampleLevel(videoTex, videoSampler, finalUV + tilt * caStrength, 0.0).r;
    let g = textureSampleLevel(videoTex, videoSampler, finalUV, 0.0).g;
    let b = textureSampleLevel(videoTex, videoSampler, finalUV - tilt * caStrength, 0.0).b;

    var color = vec3<f32>(r, g, b);

    // Specular Highlight
    // Pretend light source is at the mouse, or fixed.
    // Let's have a moving light source (mouse).
    // Normal estimation:
    // Flat surface (0,0,1) + Tilt (x,y,0)
    let normal = normalize(vec3<f32>(tilt * 2.0 + (vec2<f32>(0.5)-cellUV)*0.5, 1.0)); // Fake normal mixing tilt and bevel
    let lightDir = normalize(vec3<f32>(vecToMouse, 0.5)); // Light is above the mouse

    let spec = pow(max(dot(normal, lightDir), 0.0), 16.0) * influence;

    // Add grid lines (mortar)
    let mortar = smoothstep(0.0, 0.05, cellUV.x) * smoothstep(1.0, 0.95, cellUV.x) *
                 smoothstep(0.0, 0.05, cellUV.y) * smoothstep(1.0, 0.95, cellUV.y);

    // Darken mortar
    color = color * (0.2 + 0.8 * mortar);

    // Add specular
    color += spec * 0.8;

    // Debug: visualize cells
    // color += vec3(cellUV, 0.0) * 0.1;

    textureStore(outTex, gid.xy, vec4<f32>(color, 1.0));
}
