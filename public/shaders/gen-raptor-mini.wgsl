@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
  config: vec4<f32>,      // time, unused, resolutionX, resolutionY
  zoom_config: vec4<f32>, // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>, // x=audioIntensity (rage), other slots free
};

// core compute for generative raptors
// workgroup size 8x8 to match generator dispatch rules
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = u.config.y;
    let audioBass = u.config.y * 1.2;
    let audioMid = u.config.z;
    let audioHigh = u.config.w;
    let audioReactivity = 1.0 + audioOverall * 0.5;
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let audio = u.zoom_params.x; // rage multiplier [0,1]

    // base color accumulation
    var col: vec3<f32> = vec3<f32>(0.0);

    // simulate 8192 agents procedurally per pixel
    // each agent contributes to the color if pixel is near its position
    // CPU cost is unchanged; GPU does the heavy work
    let agentCount : u32 = 8192u;
    for (var i: u32 = 0u; i < agentCount; i = i + 1u) {
        // compute a pseudo-random seed from index
        let fi = f32(i);
        // circular orbit plus time noise
        let baseAngle = 6.2831853 * (fi / f32(agentCount)) + time * 0.3 * audioReactivity;
        let radius = 0.2 + 0.1 * sin(time * 1.5 * audioReactivity + fi * 0.002);
        var pos = vec2<f32>(0.5) + vec2<f32>(cos(baseAngle), sin(baseAngle)) * radius;

        // chase the mouse: move a tiny step toward the cursor each frame
        pos += (mouse - pos) * 0.02;

        // audio rage mode increases movement amplitude
        pos += (mouse - pos) * audio * 0.1;

        // compute distance to current pixel
        let d = distance(uv, pos);
        if (d < 0.008) {
            // base body color with a scale pattern
            let scale = fract(sin((fi + time * 10.0 * audioReactivity) * 12.9898) * 43758.5453);
            let body = mix(vec3<f32>(0.1, 0.3, 0.1), vec3<f32>(0.2, 0.8, 0.2), scale);
            col += body * (1.0 - d / 0.008);

            // claw strike effect occasionally
            let clawChance = fract(sin(fi * 78.233 + time * 40.0 * audioReactivity) * 124.123);
            if (clawChance < 0.02 + audio * 0.05) {
                // highlight with bright spike
                col += vec3<f32>(1.0, 0.5, 0.2) * (1.0 - d / 0.008);
            }
        }
    }

    // fade out background slowly to create motion trails
    let prev = textureLoad(readTexture, vec2<i32>(global_id.xy), 0).rgb;
    col = mix(prev * 0.96, col, 0.5);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
}
