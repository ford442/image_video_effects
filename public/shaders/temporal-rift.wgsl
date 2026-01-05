// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Strength, y=Radius, z=Aberration, w=Darkness
  ripples: array<vec4<f32>, 50>,
};

// Simple hash for jitter
fn hash12(p: vec2<f32>) -> f32 {
	var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Mouse Interaction
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Params
    let smearDecay = 0.9 + u.zoom_params.x * 0.09; // 0.90 to 0.99 (slow fade)
    let riftWidth = 0.05 + u.zoom_params.y * 0.2; // 0.05 to 0.25
    let chromaSep = u.zoom_params.z * 0.02; // 0.0 to 0.02
    let timeFlow = u.zoom_params.w; // Mix control

    // Input Color
    let currColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // History Color (from previous frame)
    // We add some distortion to the history read to make it "swirl" or "rift"
    // But only near the mouse or rift center?
    // Actually, let's just make the mouse drag the history.

    // Distance from mouse
    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Rift influence
    let rift = smoothstep(riftWidth, 0.0, dist);

    // If we are in the rift, we sample history with an offset (chroma sep)
    // Otherwise we just fade.

    // Read history with chroma separation
    let histR = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(chromaSep, 0.0), 0.0).r;
    let histG = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).g;
    let histB = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(chromaSep, 0.0), 0.0).b;
    let histColor = vec4<f32>(histR, histG, histB, 1.0);

    // Mix logic:
    // If rift > 0, we inject the CURRENT image strongly but perhaps distorted?
    // Or maybe the rift *reveals* the history (time echo)?
    // Let's say the mouse "paints" the current frame into the history buffer with high persistence.
    // Everywhere else, the history buffer fades to black (or to the current frame?).

    // Let's try: "Temporal Smear".
    // History buffer holds the "trails".
    // New History = mix(OldHistory * Decay, CurrentFrame, MouseInfluence)

    // If mouse is near, we blend CurrentFrame into History.
    // If mouse is far, History just decays.

    let paintFactor = rift * (0.5 + 0.5 * mouseDown); // 0 to 1

    // Calculate new history state
    // We want the trail to persist.
    // newHist = mix(histColor * smearDecay, currColor, paintFactor)
    // But we also want the background video to show through?
    // Usually trails effects add to the scene.

    // Let's make the display a mix of Current and History.
    // Display = Current + History

    // Update History:
    // It should decay.
    var nextHist = histColor * smearDecay;

    // Add current pixels to history if near mouse
    if (paintFactor > 0.01) {
        // Add current color to history
        nextHist = mix(nextHist, currColor, paintFactor);
    }

    // Output Display
    // Blend history on top of current?
    // let outColor = mix(currColor, nextHist, timeFlow);
    // Or Additive?
    let outColor = currColor + nextHist * timeFlow;

    // Write to display
    textureStore(writeTexture, global_id.xy, outColor);

    // Write to history (dataTextureA)
    // Ensure alpha is 1.0 or used?
    textureStore(dataTextureA, global_id.xy, clamp(nextHist, vec4<f32>(0.0), vec4<f32>(1.0)));
}
