// ═══════════════════════════════════════════════════════════════════
//  ASCII Glyph
//  Category: geometric
//  Features: mouse-driven, audio-reactive, animated, depth-luminance,
//            bass-character-swap, upgraded-rgba
//  Complexity: High
//  Chunks From: ascii-glyph, bass_env
//  Created: 2024-01-01
//  Upgraded: 2026-05-31
//  Batch 19 upgrade (Interactivist): wired the advertised mouse — an
//  aspect-corrected spring-damper lens (extraBuffer[133..136]) that
//  densifies glyphs under the pointer, plus click-ripple scramble
//  rings that chaotically flip characters on a ~1.2s fade.
// ═══════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=GlyphSize, y=Brightness, z=ColorAmount, w=DensityBoost
  ripples: array<vec4<f32>, 50>,  // xy=click pos (uv), z=click time
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.3 + mids * 0.1;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // ── Sliders (saved-preset contract: u.zoom_params.x/y/z/w) ───────
    // x = Glyph Size:    base cell edge in px, still breathes with bass_env
    // y = Brightness:    final glyph intensity
    // z = Color Amount:  ice-white glyph ink vs source-image color
    // w = Density Boost: pushes faint cells over the character threshold
    var glyphSize = mix(4.0, 32.0, u.zoom_params.x) * bass_env(bass, mids);
    let brightness = u.zoom_params.y;
    let colorAmount = u.zoom_params.z;
    let densityBoost = u.zoom_params.w;

    // ── Spring-damper mouse lens ─────────────────────────────────────
    // Persistent lens state lives in extraBuffer[133..136] (safe zone;
    // [0..4] engine-reserved, [5..132] engine FFT bins):
    //   [133..134] = eased lens center (uv), [135..136] = lens velocity.
    // A semi-implicit spring glides the lens toward the raw cursor.
    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    var lensPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var lensVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (lensPos.x == 0.0 && lensPos.y == 0.0 && time < 2.0) {
        lensPos = rawMouse; // first frames: snap, no fly-in from origin
        lensVel = vec2<f32>(0.0);
    }
    let springK = 0.14;
    let damping = 0.78;
    lensVel = (lensVel + (rawMouse - lensPos) * springK) * damping;
    lensPos = lensPos + lensVel;
    extraBuffer[133] = lensPos.x;
    extraBuffer[134] = lensPos.y;
    extraBuffer[135] = lensVel.x;
    extraBuffer[136] = lensVel.y;

    // Aspect-corrected distance so the lens stays circular on any canvas.
    let lensDelta = (uv - lensPos) * vec2<f32>(aspect, 1.0);
    let lensDist = length(lensDelta);
    // Holding the mouse button tightens the lens (finer type on demand).
    let mouseDown = clamp(u.zoom_config.w, 0.0, 1.0);
    let lensRadius = mix(0.30, 0.22, mouseDown);
    let mouseMask = 1.0 - smoothstep(0.0, lensRadius, lensDist);
    let lensBoost = mouseMask * (1.0 + mouseDown * 0.5);

    // Under the pointer the type resolves finer: smaller cells come first.
    glyphSize = glyphSize / (1.0 + lensBoost * 1.5);

    let pixelUV = uv * resolution;
    let cell = floor(pixelUV / glyphSize);
    let cellUV = fract(pixelUV / glyphSize);
    let cellCenter = (cell + 0.5) * glyphSize / resolution;

    // Sample luminance at cell center with depth weighting
    let centerColor = textureSampleLevel(readTexture, u_sampler, cellCenter, 0.0);
    let luma = dot(centerColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let depthLuma = mix(luma, luma * (1.0 - depth), 0.3);

    // Character density: higher for bright areas, boosted by densityBoost
    var charDensity = smoothstep(0.3, 0.9, depthLuma + densityBoost * 0.2);
    // The lens lifts density so the image resolves into finer type.
    charDensity = clamp(charDensity + lensBoost * 0.3, 0.0, 1.0);

    // ── Click ripple scramble ────────────────────────────────────────
    // Each live ripple injects a decaying hash-scramble ring at its click
    // point: rippleAge * rippleBand enters the glyph hash seed so cells
    // inside the expanding band flip characters chaotically (~1.2s fade).
    var scrambleSeed = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rippleAge = time - u.ripples[i].z;
        if (rippleAge > 0.0 && rippleAge < 1.2) {
            let fade = 1.0 - rippleAge / 1.2;
            let clickDelta = (cellCenter - u.ripples[i].xy) * vec2<f32>(aspect, 1.0);
            let clickDist = length(clickDelta);
            let ringRadius = rippleAge * 0.45;
            let rippleBand = 1.0 - smoothstep(0.0, 0.08, abs(clickDist - ringRadius));
            scrambleSeed += rippleAge * rippleBand * fade;
        }
    }

    // Bass character swap: swap glyph patterns on strong beats
    let beatSwap = hash12(cell + vec2<f32>(floor(bass * 5.0), 0.0));
    let glyphPattern = hash12(cell + vec2<f32>(beatSwap + scrambleSeed, 0.0));

    let glyphThreshold = glyphPattern;
    let isGlyph = step(glyphThreshold, charDensity);

    // Glyph SDF approximation: simple cross/dot
    let crossDist = min(abs(cellUV.x - 0.5), abs(cellUV.y - 0.5));
    let dotDist = length(cellUV - vec2<f32>(0.5));
    let glyphShape = select(1.0 - smoothstep(0.0, 0.15, crossDist), 1.0 - smoothstep(0.0, 0.2, dotDist), glyphPattern > 0.5);
    let glyphAlpha = glyphShape * isGlyph;

    // Depth-based color: foreground brighter, background darker
    let glyphColor = mix(
        vec3<f32>(0.8, 0.9, 1.0),
        centerColor.rgb * (1.0 + treble * 0.5),
        colorAmount
    );
    let depthColor = mix(vec3<f32>(0.3, 0.4, 0.5), glyphColor, depth);

    // Scrambled rings flash a cool cyan so clicks visibly scatter the type.
    let scrambleFlash = clamp(scrambleSeed, 0.0, 1.0) * glyphAlpha;
    let flashColor = vec3<f32>(0.4, 0.9, 1.0) * scrambleFlash * 0.6;

    let finalRGB = depthColor * glyphAlpha * brightness + flashColor;
    let alpha = clamp(glyphAlpha * brightness + bass * 0.05, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
