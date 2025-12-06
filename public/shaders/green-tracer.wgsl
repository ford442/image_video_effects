// ---------------------------------------------------------------
//  Green Tracer World – surreal green video effect with motion trails
//  Trails persist & fade, edges glow, film grain adds strangeness.
// ---------------------------------------------------------------
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var prevFrame:  texture_storage_2d<rgba32float, write>; // persistence
@group(0) @binding(8) var normalBuf:  texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTexC:   texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------------------

struct Uniforms {
  config:      vec4<f32>,       // x=time, y=frame, z=resX, w=resY
  zoom_params: vec4<f32>,       // x=trailLength, y=glowIntensity, z=greenTint, w=noiseAmt
  zoom_config: vec4<f32>,       // x=motionThresh, y=depthInf, z=trailFade, w=unused
  ripples:     array<vec4<f32>, 50>,
};

// ---------------------------------------------------------------
//  Helpers
// ---------------------------------------------------------------
fn hash(p: vec2<f32>) -> f32 {
    var h = fract(vec3<f32>(p.xyx) * 0.1031);
    h += dot(h, h.yzx + 33.33);
    return fract((h.x + h.y) * h.z);
}

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    let p = mix(vec4<f32>(c.bg, K.wz), vec4<f32>(c.gb, K.xy), step(c.b, c.g));
    let q = mix(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), step(p.x, c.r));
    let d = q.x - min(q.w, q.y);
    let e = 1.0e-10;
    return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// ---------------------------------------------------------------
//  Edge detection (Sobel-ish)
// ---------------------------------------------------------------
fn edgeDetect(uv: vec2<f32>, texel: vec2<f32>) -> f32 {
    let dL = textureSampleLevel(videoTex, videoSampler, uv - vec2<f32>(texel.x,0.0), 0.0).r;
    let dR = textureSampleLevel(videoTex, videoSampler, uv + vec2<f32>(texel.x,0.0), 0.0).r;
    let dU = textureSampleLevel(videoTex, videoSampler, uv - vec2<f32>(0.0,texel.y), 0.0).r;
    let dD = textureSampleLevel(videoTex, videoSampler, uv + vec2<f32>(0.0,texel.y), 0.0).r;
    return length(vec2<f32>(dR-dL, dD-dU));
}

// ---------------------------------------------------------------
//  Main compute
// ---------------------------------------------------------------
@compute @workgroup_size(8,8,1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    let uv  = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;
    let texel = 1.0 / resolution;

    // -----------------------------------------------------------------
    //  1️⃣  Parameters (sliders)
    // -----------------------------------------------------------------
    let trailLen  = u.zoom_params.x;           // 0–1 → trail persistence
    let glowInt   = u.zoom_params.y;           // glow on moving edges
    let greenTint = u.zoom_params.z;           // how green the world is
    let noiseAmt  = u.zoom_params.w;           // film grain
    let motionThresh = u.zoom_config.x * 0.1;  // motion detection sensitivity
    let depthInf  = u.zoom_config.y;           // depth influence
    let trailFade = u.zoom_config.z * 0.05 + 0.95; // trail fade rate

    // -----------------------------------------------------------------
    //  2️⃣  Read current & previous frame
    // -----------------------------------------------------------------
    let src = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    // FIX: Read from dataTexC (binding 9) instead of prevFrame (binding 7, write-only)
    let prev = textureSampleLevel(dataTexC, videoSampler, uv, 0.0).rgb;

    // -----------------------------------------------------------------
    //  3️⃣  Motion detection (difference between frames)
    // -----------------------------------------------------------------
    let motion = length(src - prev);
    let isMoving = motion > motionThresh;

    // -----------------------------------------------------------------
    //  4️⃣  Temporal persistence (trails)
    // -----------------------------------------------------------------
    var trail = prev;
    if (isMoving) {
        // Blend current frame into trail
        trail = mix(trail, src, 0.1);
    } else {
        // Fade trail
        trail = trail * trailFade;
    }
    // Store for next frame
    textureStore(prevFrame, gid.xy, vec4<f32>(trail, 1.0));

    // -----------------------------------------------------------------
    //  5️⃣  Green tint & colour grading
    // -----------------------------------------------------------------
    let greenWorld = mix(src, vec3<f32>(0.1, 1.0, 0.2), greenTint);

    // -----------------------------------------------------------------
    //  6️⃣  Glow on moving edges
    // -----------------------------------------------------------------
    let edge = edgeDetect(uv, texel);
    let glow = glowInt * smoothstep(0.0, 0.1, motion) * edge;
    let glowCol = vec3<f32>(0.0, 1.0, 0.3) * glow;

    // -----------------------------------------------------------------
    //  7️⃣  Film grain (static noise)
    // -----------------------------------------------------------------
    let grain = (hash(uv * 1000.0 + time) - 0.5) * noiseAmt;

    // -----------------------------------------------------------------
    //  8️⃣  Composite
    // -----------------------------------------------------------------
    var outCol = greenWorld + glowCol + grain;
    outCol = clamp(outCol, vec3<f32>(0.0), vec3<f32>(1.0));

    // Depth influence can modulate overall intensity
    outCol *= 1.0 - depthInf * depth * 0.3;

    textureStore(outTex, gid.xy, vec4<f32>(outCol, 1.0));
    textureStore(outDepth, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
