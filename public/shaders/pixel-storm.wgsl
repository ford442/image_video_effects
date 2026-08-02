// ---------------------------------------------------------------
//  Pixel Storm – Mouse-driven chaos
// ---------------------------------------------------------------
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
  config:      vec4<f32>,       // x=time, y=rippleCount, z=resX, w=resY
  zoom_config: vec4<f32>,       // x=time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,       // x=Strength, y=Chaos, z=Trail, w=Radius
  ripples:     array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
	var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / max(resolution.y, 1.0);
    let aspectVec = vec2<f32>(aspect, 1.0);
    let bass = plasmaBuffer[0u].x;
    let mids = plasmaBuffer[0u].y;
    let treble = plasmaBuffer[0u].z;

    // Params
    let strength = u.zoom_params.x * 0.05 * (1.0 + bass * 0.4); // Max displacement per frame
    let chaos = u.zoom_params.y;
    let trail = u.zoom_params.z; // 0=no history (clear), 1=full history
    let radiusParam = u.zoom_params.w * 0.5 + 0.05; // Effect radius

    // A heavy storm eye follows the normalized raw cursor with explicit
    // initialization, so a real top-left target cannot be mistaken for zero.
    let rawMouse = u.zoom_config.yz;
    var mousePos = vec2<f32>(extraBuffer[133u], extraBuffer[134u]);
    var mouseVelocity = vec2<f32>(extraBuffer[135u], extraBuffer[136u]);
    let stormInitialized = extraBuffer[137u] >= 0.5;
    if (!stormInitialized) {
        mousePos = rawMouse;
        mouseVelocity = vec2<f32>(0.0);
    }
    let springDt = select(0.0, clamp(time - extraBuffer[138u], 0.0005, 0.05), stormInitialized);
    let springOmega = 8.0;
    let stormAccel = springOmega * springOmega * (rawMouse - mousePos)
        - 2.0 * springOmega * mouseVelocity;
    mouseVelocity += stormAccel * springDt;
    mousePos = clamp(mousePos + mouseVelocity * springDt, vec2<f32>(-0.2), vec2<f32>(1.2));
    if (gid.x == 0u && gid.y == 0u) {
        extraBuffer[133u] = mousePos.x;
        extraBuffer[134u] = mousePos.y;
        extraBuffer[135u] = mouseVelocity.x;
        extraBuffer[136u] = mouseVelocity.y;
        extraBuffer[137u] = 1.0;
        extraBuffer[138u] = time;
    }
    let mouseDown = u.zoom_config.w;

    // Read previous state (history of displacement) or just prev image?
    // Let's make it so pixels drift. We read from the location where the pixel CAME FROM.
    // But compute shader writes to specific pixel.
    // So we calculate "where do I sample from?" (inverse advection).

    let mouseDeltaAspect = (uv - mousePos) * aspectVec;
    let dist = length(mouseDeltaAspect);

    // Wind vector (blows away from mouse)
    var wind = vec2<f32>(0.0);
    if (dist < radiusParam) {
        let dirAspect = mouseDeltaAspect / max(dist, 0.0001);
        let dir = dirAspect / aspectVec;
        let force = (1.0 - dist/radiusParam); // Stronger at center
        wind = dir * force * strength;

        // Add chaos
        if (chaos > 0.0) {
            let noise = hash12(uv * 100.0 + time) - 0.5;
            let angle = noise * 6.28 * chaos;
            let c = cos(angle);
            let s = sin(angle);
            // Rotate in aspect space, then map back to UV velocity.
            let windAspect = wind * aspectVec;
            let rotatedAspect = vec2<f32>(windAspect.x*c - windAspect.y*s, windAspect.x*s + windAspect.y*c);
            wind = rotatedAspect / aspectVec;
        }
    }

    // Per-sector FFT voices make chaos spatial instead of one global pulse.
    let angle = atan2(mouseDeltaAspect.y, mouseDeltaAspect.x);
    let sector = u32(clamp(floor((angle + 3.14159265) * 8.0 / 6.2831853), 0.0, 7.0));
    let sectorVoice = plasmaBuffer[(sector % 8u) + 1u].x;
    let audioAngle = (sectorVoice + mids * 0.2 + treble * 0.1) * chaos * 0.8;
    let audioC = cos(audioAngle);
    let audioS = sin(audioAngle);
    let audioWindAspect = wind * aspectVec;
    let audioRotatedAspect = vec2<f32>(
        audioWindAspect.x * audioC - audioWindAspect.y * audioS,
        audioWindAspect.x * audioS + audioWindAspect.y * audioC
    );
    wind = audioRotatedAspect / aspectVec;

    // Clicks seed short-lived storm cells with alternating radial/vortex flow.
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri += 1u) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.6) {
            let clickVec = (uv - ripple.xy) * aspectVec;
            let clickDist = length(clickVec);
            let radialAspect = clickVec / max(clickDist, 0.0001);
            let tangentAspect = vec2<f32>(-radialAspect.y, radialAspect.x);
            let clickDirAspect = mix(radialAspect, tangentAspect, chaos);
            let clickDir = clickDirAspect / aspectVec;
            let clickMask = smoothstep(radiusParam * 0.8, 0.0, clickDist) * exp(-age * 2.0);
            let directionSign = select(-1.0, 1.0, (ri % 2u) == 0u);
            wind += clickDir * clickMask * strength * 1.5 * directionSign;
        }
    }

    // If mouse down, suck in? Or blow harder? Let's reverse direction (suck in black hole style)
    if (mouseDown > 0.5) {
        wind = -wind * 2.0;
    }

    // Where to sample from? (uv - wind)
    let samplePos = clamp(uv - wind, vec2<f32>(0.0), vec2<f32>(1.0));

    // Sample current video frame (fresh pixels)
    let fresh = textureSampleLevel(readTexture, u_sampler, samplePos, 0.0).rgb;

    // Sample history (previous displaced pixels)
    // We also advect the history?
    // If we just read history at 'samplePos', we get the smear.
    let history = textureSampleLevel(dataTextureC, non_filtering_sampler, samplePos, 0.0).rgb;

    // Mix fresh and history based on Trail parameter
    // If Trail is high, we see mostly history (smear). If low, we see fresh video.
    // But we only want history where the effect is happening?
    // Let's mix globally.
    // Trail 1.0 = infinite feedback (don't update with fresh unless we have to?)
    // Usually mix(fresh, history, trail)

    var outCol = mix(fresh, history, trail * 0.95); // Limit max trail to avoid total freeze

    // If wind is zero, we should probably just show fresh video to reset?
    // Or if trail is high, the screen freezes.
    // Let's fade to fresh if no wind?
    if (length(wind) < 0.0001) {
       outCol = mix(outCol, fresh, 0.1); // Slow recovery
    }

    // Store
    textureStore(writeTexture, gid.xy, vec4<f32>(outCol, 1.0));

    // Store for history (dataTextureA is next frame's C)
    textureStore(dataTextureA, gid.xy, vec4<f32>(outCol, 1.0));

    // Passthrough depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
