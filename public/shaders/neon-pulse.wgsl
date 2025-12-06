// ---------------------------------------------------------------
//  Neon Pulse – Cyberpunk scanning lines
//  Vibrant, glowing lines that scan the geometry and pulse with energy.
// ---------------------------------------------------------------
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var pulseBuf:   texture_storage_2d<rgba32float, write>; // smooth persistence
@group(0) @binding(8) var normalBuf:  texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTexC:   texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------------------

struct Uniforms {
  config:      vec4<f32>,       // x=time, y=frame, z=resX, w=resY
  zoom_params: vec4<f32>,       // x=scanSpeed, y=lineThickness, z=glowIntensity, w=hue
  zoom_config: vec4<f32>,       // x=pulseRate, y=depthInf, z=gridScale, w=unused
  ripples:     array<vec4<f32>, 50>,
};

// ---------------------------------------------------------------
//  Helpers
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
//  Main compute
// ---------------------------------------------------------------
@compute @workgroup_size(8,8,1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;

    // 1️⃣ Params
    let scanSpeed  = u.zoom_params.x;
    let thickness  = u.zoom_params.y * 0.1;
    let intensity  = u.zoom_params.z;
    let baseHue    = u.zoom_params.w;
    let pulseRate  = u.zoom_config.x;
    let depthInf   = u.zoom_config.y;
    let gridScale  = u.zoom_config.z * 10.0 + 1.0;

    // 2️⃣ Sample inputs
    let src = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;

    // 3️⃣ Generate scanning grid
    // Warping UV with depth
    let warpUV = uv + vec2<f32>(depth * depthInf * 0.1); 
    let gridUV = warpUV * gridScale;
    
    // Moving scanline
    let scanOffset = time * scanSpeed;
    let grid = abs(fract(gridUV.y + scanOffset) - 0.5) + abs(fract(gridUV.x) - 0.5);
    
    // Smooth pulse
    let pulse = sin(time * pulseRate * 6.28 + depth * 5.0) * 0.5 + 0.5;
    
    // Line mask
    let lineMask = smoothstep(0.5, 0.5 - thickness, grid);
    
    // 4️⃣ Neon Colour
    let hue = fract(baseHue + depth * 0.2 + time * 0.1);
    let neonCol = hsv2rgb(hue, 0.9, 1.0);
    
    let glow = neonCol * lineMask * intensity * (1.0 + pulse);

    // 5️⃣ Composite
    // Additive blending over original video
    // Darken background slightly to make neon pop
    var outCol = src * 0.7 + glow;
    
    // 6️⃣ Persistence (light trails)
    // FIX: Read from dataTexC (binding 9)
    let prev = textureSampleLevel(dataTexC, depthSampler, uv, 0.0).rgb;
    let persist = max(prev * 0.85, outCol); // Fade out
    
    // Write to persistence buffer
    textureStore(pulseBuf, gid.xy, vec4<f32>(persist, 1.0));
    
    // Blend persistence into output for motion trails
    outCol = mix(outCol, persist, 0.3);

    textureStore(outTex, gid.xy, vec4<f32>(outCol, 1.0));
    textureStore(outDepth, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
