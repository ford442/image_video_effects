// ---------------------------------------------------------------
//  Quantum‑Chromatic Wormhole – psychedelic image/video‑filter
//  Turns any input video into a constantly‑twisting, colour‑as‑a‑
//  physical‑dimension wormhole with 4D hypersphere mapping.
// ---------------------------------------------------------------
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var persistBuf:  texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var normalBuf:   texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTexC:    texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------------------

struct Uniforms {
  config:      vec4<f32>,       // x=time, y=frame, z=resX, w=resY
  zoom_config: vec4<f32>,       // x=burstIntensity, y=voidThreshold, z=rotationSpeed, w=depthInf
  zoom_params: vec4<f32>,       // x=twistScale, y=flowStrength, z=trailLength, w=persistence
  ripples:     array<vec4<f32>, 50>,
};

// ---------------------------------------------------------------
//  RGB ↔ HSV conversions
// ---------------------------------------------------------------
fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    let p = mix(vec4<f32>(c.b, c.g, K.w, K.z), vec4<f32>(c.g, c.b, K.x, K.y), step(c.b, c.g));
    let q = mix(vec4<f32>(p.x, p.y, p.w, c.r), vec4<f32>(c.r, p.y, p.z, p.x), step(p.x, c.r));
    let d = q.x - min(q.w, q.y);
    let e = 1.0e-10;
    return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    let p = abs(fract(vec3<f32>(c.x, c.x, c.x) + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

// ---------------------------------------------------------------
//  4‑D hypersphere mapping (screen → 4D point)
// ---------------------------------------------------------------
fn to4D(uv: vec2<f32>, time: f32) -> vec4<f32> {
    // Map uv from [0,1] → [-1,1]
    let p = uv * 2.0 - 1.0;
    // Radial distance from centre
    var r = length(p);
    // Clamp to unit disc to keep mapping stable
    r = min(r, 0.999);
    // Height on the 4‑D sphere (sqrt(1 - r²) gives a 3‑D hemisphere)
    // Add a second "w" component by rotating in the (z,w) plane
    let theta = time * 0.2; // slow global rotation
    let h = sqrt(1.0 - r * r);
    let z = h * cos(theta);
    let w = h * sin(theta);
    return vec4<f32>(p, z, w);
}

// ---------------------------------------------------------------
//  Curl field from luminance (acts as velocity)
// ---------------------------------------------------------------
fn curlField(uv: vec2<f32>, texelSize: vec2<f32>) -> vec2<f32> {
    // Sample luminance at a small offset in four directions
    let Lu = textureSampleLevel(videoTex, videoSampler, uv + vec2<f32>(0.0, texelSize.y), 0.0).r;
    let Ld = textureSampleLevel(videoTex, videoSampler, uv - vec2<f32>(0.0, texelSize.y), 0.0).r;
    let Ll = textureSampleLevel(videoTex, videoSampler, uv + vec2<f32>(texelSize.x, 0.0), 0.0).r;
    let Lr = textureSampleLevel(videoTex, videoSampler, uv - vec2<f32>(texelSize.x, 0.0), 0.0).r;

    // Simple central differences → gradient
    let grad = vec2<f32>(Lr - Ll, Ld - Lu);
    // Curl of a 2‑D scalar field is a perpendicular vector
    return vec2<f32>(-grad.y, grad.x);
}

// ---------------------------------------------------------------
//  Main compute shader
// ---------------------------------------------------------------
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dimsI = textureDimensions(videoTex);
    let dims = vec2<f32>(f32(dimsI.x), f32(dimsI.y));
    if (gid.x >= u32(dimsI.x) || gid.y >= u32(dimsI.y)) {
        return;
    }

    let uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    let texelSize = 1.0 / dims;

    // -----------------------------------------------------------------
    //  Parameters from uniforms
    // -----------------------------------------------------------------
    let twistScale = u.zoom_params.x * 2.0 + 0.5;         // Hue rotation speed (0.5 - 2.5)
    let flowStrength = u.zoom_params.y * 0.8 + 0.1;       // Curl field strength (0.1 - 0.9)
    let trailLength = u.zoom_params.z * 0.05;             // Feedback warp distance (0 - 0.05)
    let persistence = u.zoom_params.w * 0.15 + 0.8;       // Temporal blend (0.8 - 0.95)
    let burstIntensity = u.zoom_config.x * 0.5;           // HDR burst strength
    let voidThreshold = u.zoom_config.y * 0.3 + 0.1;      // Darkness threshold for inversion
    let rotationSpeed = u.zoom_config.z * 0.3;            // Global rotation speed
    let depthInf = u.zoom_config.w;                        // Depth influence

    // Read depth
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;

    // -----------------------------------------------------------------
    //  Get source and previous state (feedback)
    // -----------------------------------------------------------------
    let src = textureSampleLevel(videoTex, videoSampler, uv, 0.0);
    let prevState = textureSampleLevel(dataTexC, videoSampler, uv, 0.0);

    // -----------------------------------------------------------------
    //  Build the 4‑D point and compute its phase
    // -----------------------------------------------------------------
    let p4 = to4D(uv, time * rotationSpeed);
    // Phase = angle of the (z,w) components (extra dimensions)
    let phase = atan2(p4.w, p4.z); // range (-π,π)

    // -----------------------------------------------------------------
    //  Compute the curl‑field velocity
    // -----------------------------------------------------------------
    let vel = curlField(uv, texelSize) * flowStrength;

    // -----------------------------------------------------------------
    //  Rotate hue by the phase (4D twist)
    // -----------------------------------------------------------------
    var hsv = rgb2hsv(src.rgb);
    hsv.x = fract(hsv.x + twistScale * phase / (2.0 * 3.14159265));

    // Depth influence on saturation
    hsv.y = hsv.y * (1.0 + (1.0 - depth) * depthInf * 0.3);

    // -----------------------------------------------------------------
    //  Convert back to RGB (the "new colour" before feedback)
    // -----------------------------------------------------------------
    var newRGB = hsv2rgb(hsv);

    // -----------------------------------------------------------------
    //  Energy injection for HDR "bursts" (bright pixels explode)
    // -----------------------------------------------------------------
    let lum = max(max(src.r, src.g), src.b);
    if (lum > 1.0) {
        // Add a burst whose hue follows the velocity direction
        let dirHue = fract(atan2(vel.y, vel.x) / (2.0 * 3.14159265));
        let burst = hsv2rgb(vec3<f32>(dirHue, 1.0, (lum - 1.0) * 2.0));
        newRGB = newRGB + burst * burstIntensity;
    }

    // -----------------------------------------------------------------
    //  Colour debt (negative channels) in dark regions → "void pockets"
    // -----------------------------------------------------------------
    if (hsv.z < voidThreshold) {
        newRGB = -newRGB; // creates "void pockets"
    }

    // -----------------------------------------------------------------
    //  Feedback warp – drag previous colour along the velocity
    // -----------------------------------------------------------------
    let warpedUV = clamp(uv + vel * trailLength, vec2<f32>(0.0), vec2<f32>(1.0));
    let warpedPrev = textureSampleLevel(dataTexC, videoSampler, warpedUV, 0.0).rgb;

    // -----------------------------------------------------------------
    //  Temporal blend (persistence creates trails)
    // -----------------------------------------------------------------
    let finalRGB = warpedPrev * persistence + newRGB * (1.0 - persistence);

    // Store for next frame
    textureStore(persistBuf, gid.xy, vec4<f32>(finalRGB, 1.0));

    // -----------------------------------------------------------------
    //  Output (HDR allowed for glow effects)
    // -----------------------------------------------------------------
    textureStore(outTex, gid.xy, vec4<f32>(finalRGB, 1.0));
    textureStore(outDepth, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
