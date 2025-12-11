// ---------------------------------------------------------------
//  Astral Veins – flowing luminous veins that wrap around depth.
//  ---------------------------------------------------------------
//  Binding layout (identical to all of your other shaders):
// ---------------------------------------------------------------
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;               // time, resolution, etc.
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var growthBuf:  texture_storage_2d<rgba32float, write>; // persistence
@group(0) @binding(8) var normalBuf:  texture_storage_2d<rgba32float, write>; // optional normal visualisation
@group(0) @binding(9) var dataTexC:   texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------------------

struct Uniforms {
  // x = time, y = frameCount, z = resolution.x, w = resolution.y
  config:      vec4<f32>,
  // x = speed, y = scale, z = intensity, w = hueShift
  zoom_params: vec4<f32>,
  // x = veinThickness, y = depthInfluence, z = pulseSpeed, w = unused
  zoom_config: vec4<f32>,
  // ripples – used for interactive “spores” (click to seed a vein)
  ripples:     array<vec4<f32>, 50>,
};

// ---------------------------------------------------------------
//  Utility – simple hash & value‑noise (fast, good enough for art)
// ---------------------------------------------------------------
fn hash(p: vec2<f32>) -> f32 {
    var h = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    let d = dot(h, vec3<f32>(h.y, h.z, h.x) + vec3<f32>(33.33));
    h = h + vec3<f32>(d);
    return fract((h.x + h.y) * h.z);
}
fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i + vec2<f32>(0.0,0.0)), hash(i + vec2<f32>(1.0,0.0)), u.x),
        mix(hash(i + vec2<f32>(0.0,1.0)), hash(i + vec2<f32>(1.0,1.0)), u.x), u.y);
}

// ---------------------------------------------------------------
//  FBM – 5 octaves, rotating each octave to avoid axial artefacts
// ---------------------------------------------------------------
fn fbm(p: vec2<f32>) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    var pt = p;
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    for (var i: u32 = 0u; i < 5u; i = i + 1u) {
        sum += amp * noise(pt * freq);
        pt = rot * pt * 2.0;
        amp *= 0.5;
    }
    return sum;
}

// ---------------------------------------------------------------
//  HSV → RGB (used for colour cycling)
// ---------------------------------------------------------------
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

// ---------------------------------------------------------------
//  Surface normal from depth – used for depth‑aware warping
// ---------------------------------------------------------------
fn normalFromDepth(uv: vec2<f32>, texel: vec2<f32>) -> vec3<f32> {
    let dL = textureSampleLevel(depthTex, depthSampler, uv - vec2<f32>(texel.x,0.0), 0.0).r;
    let dR = textureSampleLevel(depthTex, depthSampler, uv + vec2<f32>(texel.x,0.0), 0.0).r;
    let dU = textureSampleLevel(depthTex, depthSampler, uv - vec2<f32>(0.0,texel.y), 0.0).r;
    let dD = textureSampleLevel(depthTex, depthSampler, uv + vec2<f32>(0.0,texel.y), 0.0).r;
    let dx = (dR - dL) * 0.5;
    let dy = (dD - dU) * 0.5;
    return normalize(vec3<f32>(-dx, -dy, 1.0));
}

// ---------------------------------------------------------------
//  Main compute entry – runs per pixel
// ---------------------------------------------------------------
@compute @workgroup_size(8,8,1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    // -----------------------------------------------------------------
    //  1️⃣  Gather basic data
    // -----------------------------------------------------------------
    let resolution = u.config.zw;
    let uv  = vec2<f32>(gid.xy) / resolution;          // [0,1] screen space
    let time = u.config.x;

    // -----------------------------------------------------------------
    //  2️⃣  Uniform parameters (exposed as sliders in the UI)
    // -----------------------------------------------------------------
    let speed          = u.zoom_params.x * 0.4;                     // flow speed
    let scale          = mix(0.4, 3.0, u.zoom_params.y);            // noise scale
    let intensity      = u.zoom_params.z;                           // glow strength
    let hueShift       = u.zoom_params.w;                           // colour cycle offset
    let veinThickness  = u.zoom_config.x;                           // how thin/thick veins are
    let depthInfluence = u.zoom_config.y;                           // 0 = ignore depth, 1 = fully follow geometry
    let pulseSpeed     = u.zoom_config.z;                           // pulsation rate

    // -----------------------------------------------------------------
    //  3️⃣  Depth & normal (used for warping the flow field)
    // -----------------------------------------------------------------
    let texel = 1.0 / resolution;
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    let normal = normalFromDepth(uv, texel);

    // ---------------------------------------------------------------
    //  4️⃣  Domain‑warped flow field
    // ---------------------------------------------------------------
    // Base coordinate, scaled by the user‑controlled "scale"
    var p = uv * scale;

    // First warp – a slow moving noise that creates large‑scale currents
    let q = vec2<f32>(
        fbm(p + vec2<f32>(0.0,0.0) + time * speed),
        fbm(p + vec2<f32>(5.2,1.3) + time * speed)
    );

    // Second warp – adds finer turbulence
    let r = vec2<f32>(
        fbm(p + 4.0 * q + vec2<f32>(1.7,9.2) + time * speed * 0.7),
        fbm(p + 4.0 * q + vec2<f32>(8.3,2.8) + time * speed * 0.7)
    );

    // Final noise – the raw “vein density”
    let f = fbm(p + 4.0 * r + time * speed * 0.3);

    // ---------------------------------------------------------------
    //  5️⃣  Convert the scalar field into thin veins
    // ---------------------------------------------------------------
    // Gradient magnitude gives us “edges” of the noise – those become veins
    let grad = vec2<f32>(
        fbm(p + vec2<f32>(0.01,0.0) + time * speed) - fbm(p - vec2<f32>(0.01,0.0) + time * speed),
        fbm(p + vec2<f32>(0.0,0.01) + time * speed) - fbm(p - vec2<f32>(0.0,0.01) + time * speed)
    );
    let gradMag = length(grad);

    // Thin‑line mask: the higher the gradient, the brighter the vein
    // “veinThickness” pushes the threshold – larger values make thicker veins
    let veinMask = smoothstep(veinThickness, veinThickness + 0.02, gradMag);

    // ---------------------------------------------------------------
    //  6️⃣  Depth‑aware warping (veins follow geometry)
    // ---------------------------------------------------------------
    // The normal is used to push the uv a little towards the surface.
    // When depthInfluence = 0 → no warping; =1 → full warping.
    let warpedUV = uv + normal.xy * depthInfluence * 0.02;

    // ---------------------------------------------------------------
    //  7️⃣  Colour & pulsation
    // ---------------------------------------------------------------
    // Base hue cycles over time + user hueShift
    let hue = fract(hueShift + time * 0.1);
    let baseCol = hsv2rgb(hue, 0.8, 1.0);

    // Add a subtle pulse that makes the veins “breathe”
    let pulse = 0.5 + 0.5 * sin(time * pulseSpeed * 6.2831);
    let glow = pow(veinMask, 1.5) * intensity * pulse;

    // Final vein colour (glowing, additive)
    let veinCol = baseCol * glow;

    // ---------------------------------------------------------------
    //  8️⃣  Temporal persistence (trailing glow)
    // ---------------------------------------------------------------
    // Read previous frame’s growth buffer (stores a single‑channel “glow”)
    // MODIFIED: Use dataTextureC (read-only) instead of growthBuf (write-only)
    var prev = textureSampleLevel(dataTexC, depthSampler, uv, 0.0).r;
    // Fade out old glow and add the new one
    prev = prev * 0.94 + glow * 0.06;
    // Store for next frame
    textureStore(growthBuf, gid.xy, vec4<f32>(prev,0.0,0.0,1.0));

    // Use the persisted glow to give a soft halo around the veins
    let halo = prev * 0.4;

    // ---------------------------------------------------------------
    //  9️⃣  Composite over the original video frame
    // ---------------------------------------------------------------
    let videoCol = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgb;
    // Additive blend for the bright veins + a subtle screen‑blend for the halo
    var outCol = videoCol + veinCol;
    outCol = 1.0 - (1.0 - outCol) * (1.0 - vec3<f32>(halo));

    // ---------------------------------------------------------------
    //  🔟  Write final colour & depth
    // ---------------------------------------------------------------
    textureStore(outTex, gid.xy, vec4<f32>(outCol,1.0));
    textureStore(outDepth, gid.xy, vec4<f32>(depth,0.0,0.0,0.0));
}
