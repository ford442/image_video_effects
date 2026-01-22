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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;

    // Parameters
    let radius = mix(0.1, 0.5, u.zoom_params.x); // Portal Radius
    let segments = floor(mix(3.0, 16.0, u.zoom_params.y)); // Number of segments
    let rotationSpeed = u.zoom_params.z * 0.5;
    let hardness = mix(0.01, 0.2, u.zoom_params.w);

    // Mouse Interaction
    let mouse = u.zoom_config.yz; // Mouse UV (0-1)

    // Calculate distance to mouse (corrected for aspect ratio)
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Portal Mask
    // 1 inside portal, 0 outside. Smooth edge.
    let mask = 1.0 - smoothstep(radius, radius + hardness, dist);

    var finalUV = uv;

    if (mask > 0.0) {
        // We are inside the portal (or in the blend zone)
        // Convert to Polar relative to mouse
        let rel = uv - mouse;
        // Correct aspect for angle calculation? Ideally yes, but kaleidoscopes often work in UV space.
        // If we want perfect circular symmetry, we need to correct aspect, but then mapping back is tricky.
        // Let's stick to UV space for simplicity, but it might stretch if aspect is not 1.0.
        // To fix aspect stretch:
        let relCorrected = rel * vec2<f32>(aspect, 1.0);
        var angle = atan2(relCorrected.y, relCorrected.x);
        var rad = length(relCorrected);

        // Kaleidoscope Logic
        let segmentAngle = 6.2831853 / segments;

        // Rotate the entire system over time
        angle = angle + time * rotationSpeed;

        // Modulo Angle
        // Standard Kaleido: map angle to [0, segmentAngle]
        // But we want mirroring to make it seamless.

        // Normalize angle to 0..2PI
        // atan2 is -PI to PI
        if (angle < 0.0) { angle += 6.2831853; }

        // Determine segment index
        // let index = floor(angle / segmentAngle);

        // Local angle within segment
        var localAngle = angle % segmentAngle;

        // Mirroring: if we are in the second half of the segment (or just use abs)
        // Better approach for mirroring:
        // We essentially fold the space.
        // Let's try: angle = abs(mod(angle, segmentAngle) - segmentAngle/2)
        // Wait, standard kaleido is:
        // var a = mod(angle, segmentAngle);
        // if (a > segmentAngle * 0.5) a = segmentAngle - a;

        // Let's use a simpler folding
        var a = (angle % segmentAngle);
        if (a > segmentAngle * 0.5) {
            a = segmentAngle - a;
        }

        // Now map back to vector
        // We want to sample from the center outwards?
        // Or sample the image at the mouse position + offset?
        // Let's reconstruct the vector
        let newDir = vec2<f32>(cos(a), sin(a));

        // We map this back to UV.
        // We need to inverse the aspect correction for the final UV
        // relCorrected was (dx * aspect, dy)
        // newRelCorrected = newDir * rad
        // newRel = (newRelCorrected.x / aspect, newRelCorrected.y)

        let newRelCorrected = newDir * rad;
        let newRel = vec2<f32>(newRelCorrected.x / aspect, newRelCorrected.y);

        // Sample relative to mouse to keep the center consistent
        let kaleidoUV = mouse + newRel;

        // Mix UVs
        finalUV = mix(uv, kaleidoUV, mask);
    }

    // Border Glow
    let border = smoothstep(radius, radius + 0.01, dist) * (1.0 - smoothstep(radius + 0.01, radius + 0.02 + hardness, dist));
    let borderColor = vec4<f32>(0.5, 0.8, 1.0, 1.0) * border * 5.0;

    var col = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    // Add border
    col = col + borderColor;

    textureStore(writeTexture, global_id.xy, col);
}
