// Spectral Vortex - Psychedelic Feedback Shader
// Accumulates "phase" in the depth buffer and uses it to distort and hue-shift the source image.

@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex: texture_2d<f32>;
@group(0) @binding(2) var outTex: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex: texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var feedbackOut: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var normalBuf: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var feedbackTex: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=TwistScale, y=DistortionStep, z=ColorShift, w=Unused
  ripples: array<vec4<f32>, 50>,
};

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let x = c * (1.0 - abs(((h * 6.0) % 2.0) - 1.0));
    let m = v - c;
    
    var rgb = vec3<f32>(0.0, 0.0, 0.0);
    if (h < 1.0/6.0) { rgb = vec3<f32>(c, x, 0.0); }
    else if (h < 2.0/6.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h < 3.0/6.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h < 4.0/6.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h < 5.0/6.0) { rgb = vec3<f32>(x, 0.0, c); }
    else { rgb = vec3<f32>(c, 0.0, x); }
    
    return rgb + m;
}

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let cmax = max(c.r, max(c.g, c.b));
    let cmin = min(c.r, min(c.g, c.b));
    let delta = cmax - cmin;
    
    var h = 0.0;
    if (delta > 0.0) {
        if (cmax == c.r) { h = (c.g - c.b) / delta % 6.0; }
        else if (cmax == c.g) { h = (c.b - c.r) / delta + 2.0; }
        else { h = (c.r - c.g) / delta + 4.0; }
        h = h / 6.0;
        if (h < 0.0) { h = h + 1.0; }
    }
    
    let s = select(0.0, delta / cmax, cmax > 0.0);
    return vec3<f32>(h, s, cmax);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let texelSize = 1.0 / resolution;
    
    // Parameters
    let twistScale = u.zoom_params.x;     // Default ~2.0
    let distortionStep = u.zoom_params.y; // Default ~0.02
    let colorShift = u.zoom_params.z;     // Default ~0.1
    
    // 1. Calculate Curl of Source Image Luminance
    let l = textureSampleLevel(videoTex, videoSampler, uv - vec2<f32>(texelSize.x, 0.0), 0.0).r;
    let r = textureSampleLevel(videoTex, videoSampler, uv + vec2<f32>(texelSize.x, 0.0), 0.0).r;
    let t = textureSampleLevel(videoTex, videoSampler, uv - vec2<f32>(0.0, texelSize.y), 0.0).r;
    let b = textureSampleLevel(videoTex, videoSampler, uv + vec2<f32>(0.0, texelSize.y), 0.0).r;
    
    let dx = (r - l) * 0.5;
    let dy = (b - t) * 0.5;
    
    // Curl vector (velocity)
    let vel = vec2<f32>(dy, -dx) * 10.0; // Amplify
    
    // 2. Accumulate Phase in Depth Buffer
    let prevPhase = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    
    // Update phase: rotate based on local curl magnitude
    let curlMag = length(vel);
    let newPhase = prevPhase + curlMag * 0.1 + 0.01; // Constant drift + curl-driven spin
    
    // Write new phase for next frame
    textureStore(outDepth, global_id.xy, vec4<f32>(newPhase, 0.0, 0.0, 0.0));
    
    // 3. Distort UVs based on Phase and Velocity
    // We use the accumulated phase to rotate the sampling vector
    let angle = newPhase * twistScale;
    let s = sin(angle);
    let c = cos(angle);
    let rotMat = mat2x2<f32>(c, -s, s, c);
    
    // Distort UV
    let offset = rotMat * vel * distortionStep * (1.0 + sin(u.config.x * 0.5));
    let distortedUV = uv + offset;
    
    // 4. Sample Source with Distortion
    let srcCol = textureSampleLevel(videoTex, videoSampler, distortedUV, 0.0);
    
    // 5. Apply Hue Rotation
    var hsv = rgb2hsv(srcCol.rgb);
    hsv.x = fract(hsv.x + angle * 0.1 + colorShift * u.config.x); // Rotate hue over time and phase
    hsv.z = hsv.z * (1.0 + curlMag * 2.0); // Brighten high-energy areas (Energy Injection)
    
    // 6. Color Debt (Invert darks)
    var finalRGB = hsv2rgb(hsv.x, hsv.y, hsv.z);
    if (hsv.z < 0.2) {
        finalRGB = 1.0 - finalRGB;
    }
    
    textureStore(outTex, global_id.xy, vec4<f32>(finalRGB, 1.0));
}
