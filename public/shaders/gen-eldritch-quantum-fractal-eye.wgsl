// ----------------------------------------------------------------
// Eldritch-Quantum Fractal-Eye
// Category: generative
// ----------------------------------------------------------------
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

// --- UNIFORMS ---
struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};
fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(controlled, color.a);
}


fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(vec2<f32>(c, -s), vec2<f32>(s, c));
}

// Math/Hash functions
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var p_mut = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                          dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                          dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(p_mut) * 43758.5453123);
}

// Voronoi 3D
fn voronoi3D(x: vec3<f32>) -> vec2<f32> {
    let p = floor(x);
    let f = fract(x);
    var res = vec2<f32>(8.0, 8.0);
    for(var k = -1; k <= 1; k++) {
        for(var j = -1; j <= 1; j++) {
            for(var i = -1; i <= 1; i++) {
                let b = vec3<f32>(f32(i), f32(j), f32(k));
                let r = b - f + hash3(p + b);
                let d = dot(r, r);
                if(d < res.x) {
                    res.y = res.x;
                    res.x = d;
                } else if(d < res.y) {
                    res.y = d;
                }
            }
        }
    }
    return vec2<f32>(sqrt(res.x), sqrt(res.y));
}

fn sdfEye(p: vec3<f32>, mouseRot: mat2x2<f32>, time: f32, dilation: f32, iters: i32) -> f32 {
    // Basic sphere bounds
    var p_rot = p;
    p_rot.y = p_rot.y * mouseRot[0][0] + p_rot.z * mouseRot[0][1];
    p_rot.z = p_rot.y * mouseRot[1][0] + p_rot.z * mouseRot[1][1];
    p_rot.x = p_rot.x * mouseRot[0][0] + p_rot.y * mouseRot[0][1];
    p_rot.y = p_rot.x * mouseRot[1][0] + p_rot.y * mouseRot[1][1];

    let r = length(p_rot);
    let sphereDist = r - 2.5;

    // Pupil singularity
    let pupilDist = length(p_rot.xy) - (0.3 + dilation * 0.5);

    // KIFS Fractal Iris
    var z = p_rot;
    var scale = 1.0;
    for(var i = 0; i < iters; i++) {
        z = abs(z) - vec3<f32>(0.2, 0.2, 0.2);
        let r2 = dot(z, z);
        let k = max(1.2 / r2, 1.0);
        z *= k;
        scale *= k;
    }
    let fractalDist = length(z) / scale - 0.05;

    return max(sphereDist, min(fractalDist, pupilDist));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }
    let uv = (vec2<f32>(global_id.xy) - 0.5 * res) / res.y;

    let time = u.config.x;
    let audioBass = plasmaBuffer[0].x; // 0 to 1

    // Sliders
    let fractalIters = i32(u.zoom_params.x); // 1 to 15
    let dilationIntensity = u.zoom_params.y; // 0 to 1
    let plasmaDensity = u.zoom_params.z; // 0.1 to 10
    let colorShift = u.zoom_params.w; // -1 to 1

    // Sentient mouse tracking (eased)
    // Map mouse [-1, 1]
    let mx = (u.zoom_config.y / res.x) * 2.0 - 1.0;
    let my = (u.zoom_config.z / res.y) * 2.0 - 1.0;
    // Simple rotation based on mouse
    let rotX = rotate2D(my * 1.5);
    let rotY = rotate2D(mx * 1.5);

    // Dilation
    let dilation = audioBass * dilationIntensity + (u.zoom_config.w * 0.5); // React to bass and click

    // Raymarching setup
    var ro = vec3<f32>(0.0, 0.0, -5.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var max_t = 15.0;
    var steps = 0;
    var p = vec3<f32>(0.0);
    var d = 0.0;

    for(var i = 0; i < 100; i++) {
        p = ro + rd * t;
        d = sdfEye(p, rotX, time, dilation, fractalIters);
        if(d < 0.001 || t > max_t) { break; }
        t += d;
        steps++;
    }

    var finalColor = vec3<f32>(0.0);

    if (t < max_t) {
        // We hit the eye
        let v = voronoi3D(p * plasmaDensity + time);
        let plasma = smoothstep(0.1, 0.2, v.y - v.x);

        // Base color
        var col = vec3<f32>(0.1, 0.0, 0.3); // Deep abyssal purple

        // Sclera Veins
        col += vec3<f32>(0.0, 1.0, 0.8) * plasma * 2.0; // Bioluminescent cyan

        // Iris glow
        let pupilDist = length(p.xy); // Simplified pupil check
        if (pupilDist < (0.5 + dilation)) {
             col = vec3<f32>(1.0, 0.0, 0.5) * (1.0 - pupilDist); // Neon magenta
        }

        // Fake normal / lighting
        let n = normalize(p);
        let light = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, light), 0.0);
        col *= (diff + 0.2);

        // Color shift
        if (colorShift > 0.0) {
           col = mix(col, col.zxy, colorShift);
        } else {
           col = mix(col, col.yzx, -colorShift);
        }

        finalColor = col;
    } else {
        // Volumetric background glow based on distance to pupil axis
        let axisDist = length(uv);
        finalColor += vec3<f32>(0.5, 0.0, 1.0) * (0.1 / (axisDist + 0.01)) * audioBass;
    }

    textureStore(writeTexture, global_id.xy, applyGenerativePrimaryControls(vec4<f32>(finalColor, 1.0)));
}
