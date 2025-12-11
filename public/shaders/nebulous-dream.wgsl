// ---------------------------------------------------------------
//  Nebulous Dream - A swirling vortex of rainbow candy clouds.
//  Fractal noise creates clouds, which are warped by a flow field
//  and colored by a shifting rainbow gradient. Video brightness
//  influences cloud density and saturation.
// ---------------------------------------------------------------
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;

// Using the persistence buffer for "smoky trails"
@group(0) @binding(7) var historyBuf: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var unusedBuf:  texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var historyTex: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config:      vec4<f32>,       // x=time, y=frame, z=resX, w=resY
  zoom_params: vec4<f32>,       // x=cloudScale, y=flowSpeed, z=colorSpeed, w=persistence
  zoom_config: vec4<f32>,       // x=cloudSharpness, y=satBoost, z=depthInf, w=blendStrength
  ripples:     array<vec4<f32>, 50>,
};

// ---------------------------------------------------------------
//  Noise & Color Utilities
// ---------------------------------------------------------------
fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 = p3 + (dot(p3, p3 + vec3<f32>(33.33)));
    return fract((p3.x + p3.y) * p3.z);
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    let x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

// Fractal Brownian Motion (FBM) for cloud noise
fn fbm(p: vec2<f32>) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 2.0;
    for (var i: i32 = 0; i < 5; i = i + 1) {
        value = value + amplitude * (hash21(p * frequency) - 0.5);
        frequency = frequency * 2.1;
        amplitude = amplitude * 0.5;
    }
    return value;
}

// ---------------------------------------------------------------
//  Main Compute
// ---------------------------------------------------------------
@compute @workgroup_size(8,8,1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dimsI = textureDimensions(videoTex);
    let dims = vec2<f32>(f32(dimsI.x), f32(dimsI.y));
    if (gid.x >= u32(dimsI.x) || gid.y >= u32(dimsI.y)) {
        return;
    }

    let uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    
    // -----------------------------------------------------------------
    //  1️⃣  Parameters
    // -----------------------------------------------------------------
    let cloudScale = u.zoom_params.x * 9.0 + 1.0;           // 1 - 10
    let flowSpeed = u.zoom_params.y * 0.4;                   // 0 - 0.4
    let colorSpeed = u.zoom_params.z * 0.2;                  // 0 - 0.2
    let persistence = u.zoom_params.w * 0.95;                // 0 - 0.95
    let cloudSharpness = u.zoom_config.x * 0.4;              // 0 - 0.4
    let satBoost = u.zoom_config.y * 0.3 + 0.7;             // 0.7 - 1.0
    let depthInf = u.zoom_config.z;                          // 0 - 1
    let blendStrength = u.zoom_config.w * 0.5 + 0.3;        // 0.3 - 0.8

    // Sample depth for depth-aware effects
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;

    // -----------------------------------------------------------------
    //  2️⃣  Create a swirling flow field
    // -----------------------------------------------------------------
    // Use FBM to create a vector field that will distort the UVs
    let flow_uv = uv * cloudScale * 0.3;
    let q = vec2<f32>(
        fbm(flow_uv + time * flowSpeed * 0.1),
        fbm(flow_uv + vec2<f32>(5.2, 1.3) + time * flowSpeed * 0.15)
    );
    
    // Use another FBM layer to stir the first one, creating more complex motion
    let r_uv = uv * cloudScale * 1.2 + q * 2.5;
    let r = vec2<f32>(
        fbm(r_uv + time * flowSpeed * 0.2),
        fbm(r_uv + vec2<f32>(8.3, 2.8) + time * flowSpeed * 0.25)
    );
    
    // Depth influences distortion amount (far = more distortion)
    let depthDistort = 1.0 + (1.0 - depth) * depthInf * 0.5;
    
    // This is our final distorted UV for sampling the clouds
    let distortedUV = uv + q * 0.2 * depthDistort + r * 0.1 * depthDistort;
    
    // -----------------------------------------------------------------
    //  3️⃣  Generate the Cloud Density
    // -----------------------------------------------------------------
    // Sample the cloud noise with the distorted coordinates
    let cloudNoise = fbm(distortedUV * cloudScale);
    
    // Reshape the noise to create more defined, billowy cloud shapes
    let cloudDensity = smoothstep(0.0, cloudSharpness + 0.1, abs(cloudNoise) * 3.0);

    // -----------------------------------------------------------------
    //  4️⃣  Generate Rainbow Candy Colors
    // -----------------------------------------------------------------
    // The base hue shifts over time and with position, creating flowing rainbows
    let baseHue = fract(distortedUV.x + distortedUV.y * 0.5 + time * colorSpeed);
    
    // Read the source video to influence the colors
    let srcColor = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgb;
    let luminance = dot(srcColor, vec3<f32>(0.299, 0.587, 0.114));
    
    // In bright areas of the video, make clouds more saturated and brighter
    let saturation = mix(0.7, satBoost, luminance);
    let value = mix(0.5, 1.0, luminance);
    
    let cloudColor = hsv2rgb(baseHue, saturation, value);

    // -----------------------------------------------------------------
    //  5️⃣  Blend Clouds with Source Video
    // -----------------------------------------------------------------
    // Where the cloud density is high, we see the rainbow cloud color.
    let blendFactor = cloudDensity * smoothstep(0.1, 0.5, luminance) * blendStrength;
    let blendedColor = mix(srcColor, cloudColor, blendFactor);
    
    // -----------------------------------------------------------------
    //  6️⃣  Feedback Loop for Smoky Trails
    // -----------------------------------------------------------------
    // Read the result from the previous frame
    let prevFrame = textureSampleLevel(historyTex, depthSampler, uv, 0.0).rgb;
    
    // Blend the current frame with the dimmed previous frame
    let finalColor = mix(blendedColor, prevFrame, persistence);
    
    // Store this frame's result for the next frame to read
    textureStore(historyBuf, gid.xy, vec4<f32>(finalColor, 1.0));

    // -----------------------------------------------------------------
    //  7️⃣  Output
    // -----------------------------------------------------------------
    textureStore(outTex, gid.xy, vec4<f32>(finalColor, 1.0));
    textureStore(outDepth, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
