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
  zoom_params: vec4<f32>,  // x=GridScale, y=Intensity, z=Jitter, w=Threshold
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let time = u.config.x;

    // Normalize coordinates
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Parameters
    let gridScale = mix(20.0, 100.0, u.zoom_params.x); // x: Grid Scale
    let intensity = u.zoom_params.y;                  // y: Intensity/Overload
    let jitterStrength = u.zoom_params.z;             // z: Jitter Amount
    let edgeThreshold = u.zoom_params.w;              // w: Edge Threshold

    // Mouse interaction
    let mouse = u.zoom_config.yz;
    let aspectRatio = resolution.x / resolution.y;
    let uv_corrected = vec2<f32>(uv.x * aspectRatio, uv.y);
    let mouse_corrected = vec2<f32>(mouse.x * aspectRatio, mouse.y);
    let dist = distance(uv_corrected, mouse_corrected);

    // Calculate influence (closer to mouse = more effect)
    // If mouse is at (0,0) [initial state], reduce effect
    let hasMouse = step(0.001, mouse.x + mouse.y);
    let influence = smoothstep(0.4, 0.0, dist) * hasMouse * (1.0 + intensity * 2.0);

    // Grid generation
    let gridUV = uv * gridScale;
    let gridID = floor(gridUV);
    let gridLine = smoothstep(0.95, 1.0, fract(gridUV.x)) + smoothstep(0.95, 1.0, fract(gridUV.y));
    let isGrid = clamp(gridLine, 0.0, 1.0);

    // Circuit "nodes" (random points on grid)
    let node = step(0.9, hash21(gridID));

    // Apply jitter based on influence
    var sampleUV = uv;
    if (influence > 0.1) {
        let jitter = (vec2<f32>(hash21(uv + time), hash21(uv + time + 10.0)) - 0.5) * jitterStrength * influence * 0.1;
        sampleUV = uv + jitter;
    }

    // Sample texture
    let color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Edge detection (simple luminance difference)
    let offset = 1.0 / resolution;
    let left = textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(offset.x, 0.0), 0.0);
    let right = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(offset.x, 0.0), 0.0);
    let up = textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(0.0, offset.y), 0.0);
    let down = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(0.0, offset.y), 0.0);

    let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let lumaL = dot(left.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let lumaR = dot(right.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let lumaU = dot(up.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let lumaD = dot(down.rgb, vec3<f32>(0.299, 0.587, 0.114));

    let edgeX = lumaL - lumaR;
    let edgeY = lumaU - lumaD;
    let edge = sqrt(edgeX * edgeX + edgeY * edgeY);

    // Determine output color
    var finalColor = color.rgb;

    // Apply "Circuit" effect
    let isEdge = step(edgeThreshold, edge);

    // Green matrix/circuit look
    let circuitColor = vec3<f32>(0.0, 0.8, 0.2); // Circuit green
    let overloadColor = vec3<f32>(0.5, 0.8, 1.0); // Electric blue/white

    if (isEdge > 0.5 || isGrid > 0.5) {
        // Mix based on influence
        let glow = mix(circuitColor, overloadColor, influence);
        finalColor = mix(finalColor, glow, 0.5 + influence * 0.5);
    }

    // Overload flash
    if (influence > 0.5 && node > 0.5) {
         // Flashing nodes near mouse
         let flash = sin(time * 20.0 + hash21(gridID) * 6.28) * 0.5 + 0.5;
         finalColor = mix(finalColor, vec3<f32>(1.0), flash * influence);
    }

    // Scanline effect just for style
    let scanline = sin(uv.y * resolution.y * 0.5) * 0.1;
    finalColor = finalColor - scanline;

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));
}
