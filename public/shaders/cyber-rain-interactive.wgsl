// ────────────────────────────────────────────────────────────────────────────────
//  Cyber Rain Interactive
//  Digital rain effect that interacts with image luminance and mouse.
// ────────────────────────────────────────────────────────────────────────────────
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

fn hash12(p: vec2<f32>) -> f32 {
	var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    let uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    let aspect = dims.x / dims.y;

    // Params
    let speed = u.zoom_params.x * 2.0 + 0.2;
    let density = u.zoom_params.y; // Used to control column width/count
    let glitch = u.zoom_params.z;
    let trailLen = u.zoom_params.w * 5.0 + 1.0;

    let mouse = u.zoom_config.yz;
    let click = u.zoom_config.w;

    // Grid for rain columns
    let cols = 50.0 + density * 100.0;
    let cell = floor(uv * vec2<f32>(cols, cols / aspect));

    // Random speed per column
    let colRand = hash12(vec2<f32>(cell.x, 0.0));
    let fallSpeed = speed * (0.5 + colRand * 1.5);

    // Vertical position in flow
    let yPos = uv.y + time * fallSpeed;

    // Character switching
    let charStep = floor(yPos * 20.0);
    let charRand = hash12(vec2<f32>(cell.x, charStep));

    // Trail calculation
    let dropPos = fract(yPos); // 0-1 repeating
    // We want the 'head' to be at a specific spot.
    // Let's make a continuous stream that resets.

    // Simpler Matrix Rain Logic:
    // y is screen coord. Rain falls down (y increases or decreases depending on coord system).
    // UV y is 0 at top usually? No, in WGSL texture coords, 0,0 is usually top-left or bottom-left depending on API, but let's assume standard UV.
    // Let's assume falling down means UV y increasing? Or decreasing.
    // Usually UV (0,0) is top-left in web/canvas?
    // Actually in WebGPU it matches Metal/Vulkan, usually (0,0) top-left for textures if loaded from image?
    // Wait, let's just make it flow.

    let flowTime = time * fallSpeed;
    let gridY = floor(uv.y * cols / aspect);

    // Determine if this cell is active based on a moving head
    // Head moves down.
    let headY = fract(time * fallSpeed + colRand * 10.0); // 0 to 1

    // Distance from head
    let dist = (headY - uv.y);
    if (dist < 0.0) { dist += 1.0; } // Wrap around

    // Underlying image interaction
    let imgColor = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgb;
    let luma = dot(imgColor, vec3<f32>(0.299, 0.587, 0.114));

    // Mouse Interaction: Disrupt the rain
    let mouseDist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));
    let mouseRepel = smoothstep(0.2, 0.0, mouseDist);

    // If mouse is near, brighten and maybe change character

    // Render the character (simplified as a brightness block with some noise)
    var brightness = smoothstep(1.0 / trailLen, 0.0, dist); // Trail tail

    // Head is bright white
    if (dist < 0.02) { brightness = 2.0; }

    // Glitch effect: displace UV slightly
    if (hash12(vec2<f32>(time, uv.y)) < glitch * 0.1) {
        brightness = 0.0;
    }

    // Colorize
    var rainColor = vec3<f32>(0.0, 1.0, 0.2) * brightness;

    // Mix with underlying image luminance
    // If image is bright, rain is brighter or different color
    if (luma > 0.5) {
        rainColor = vec3<f32>(0.8, 1.0, 0.8) * brightness;
    }

    // Mouse effect
    rainColor += vec3<f32>(mouseRepel, mouseRepel * 0.5, 1.0) * mouseRepel * 2.0;

    // Final composite
    let final = mix(imgColor * 0.1, rainColor, brightness);

    textureStore(outTex, gid.xy, vec4<f32>(final, 1.0));
    
    // Pass through depth
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    textureStore(outDepth, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
