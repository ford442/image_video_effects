// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4 (Use these for ANY float sliders)
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Mouse interaction
    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    // Parameters
    let rotationSpeed = (u.zoom_params.x - 0.5) * 4.0; // Speed of auto-rotation
    let scratchAmount = u.zoom_params.y; // How much mouse X affects rotation (Scratching)
    let wobble = u.zoom_params.z;
    let noiseIntensity = u.zoom_params.w;

    // Center of the record
    let center = vec2<f32>(0.5, 0.5);
    let dir = uv - center;
    let dirCorrected = vec2<f32>(dir.x * aspect, dir.y);
    let dist = length(dirCorrected);
    let angle = atan2(dirCorrected.y, dirCorrected.x);

    // Calculate Rotation
    // Base rotation
    var rot = time * rotationSpeed;

    // Scratching: Add offset based on Mouse X relative to center
    // If mouse is at left, rewind. Right, fast forward.
    // Or simpler: Map MouseX directly to angle offset?
    // Let's do: Mouse X determines a static offset, allowing manual "scrubbing" if speed is 0.
    let scratchOffset = (mousePos.x - 0.5) * 10.0 * scratchAmount;
    rot = rot + scratchOffset;

    // Wobble (simulating warped vinyl)
    // Wobble depends on angle and time
    let wobbleOffset = sin(angle * 2.0 + time * 5.0) * 0.02 * wobble * dist;

    // Calculate new sampling coordinates
    let finalAngle = angle - rot;

    // Convert back to UV
    // We need to rotate the original 'dir' vector by -rot
    // But since we are sampling, we rotate the UV coordinate "backwards" relative to rotation

    let cosA = cos(rot);
    let sinA = sin(rot);

    // Rotate vector (x, y)
    // x' = x cos - y sin
    // y' = x sin + y cos
    // Note: aspect correction needed for rotation to be circular

    let rotatedDirX = dirCorrected.x * cosA - dirCorrected.y * sinA;
    let rotatedDirY = dirCorrected.x * sinA + dirCorrected.y * cosA;

    // Map back to UV space (undo aspect)
    let sampleUV = vec2<f32>(rotatedDirX / aspect, rotatedDirY) + center + vec2<f32>(wobbleOffset, wobbleOffset);

    // Sample texture
    var color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Add noise/grain based on radius (grooves)
    let grooveNoise = fract(sin(dot(uv * time, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    let grooveIntensity = (sin(dist * 400.0) * 0.5 + 0.5) * noiseIntensity;

    color = mix(color, vec4<f32>(grooveNoise, grooveNoise, grooveNoise, 1.0), grooveIntensity * 0.2);

    // Fade out edges if rotated outside
    // Simple bounds check? textureSample usually clamps or repeats.
    // Let's assume repeat is fine, or clamp. But for "record" look, maybe black outside?
    // Let's leave it as is for "image rotation".

    textureStore(writeTexture, global_id.xy, color);

    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
