// ═══════════════════════════════════════════════════════════════════
//  4D Projection Dream Weavers
//  Category: generative
//  Description: Smooth, continuous slicing and projection through
//  higher-dimensional fractals. Mouse controls navigation through
//  the extra two dimensions. Audio affects fractal parameters.
//  Complexity: High
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// 4D rotation in the XW plane
fn rot4XW(v: vec4<f32>, angle: f32) -> vec4<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec4<f32>(
        c * v.x - s * v.w,
        v.y,
        v.z,
        s * v.x + c * v.w
    );
}

// 4D rotation in the YZ plane
fn rot4YZ(v: vec4<f32>, angle: f32) -> vec4<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec4<f32>(
        v.x,
        c * v.y - s * v.z,
        s * v.y + c * v.z,
        v.w
    );
}

// 4D rotation in the ZW plane
fn rot4ZW(v: vec4<f32>, angle: f32) -> vec4<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec4<f32>(
        v.x,
        v.y,
        c * v.z - s * v.w,
        s * v.z + c * v.w
    );
}

// 4D rotation in the XY plane
fn rot4XY(v: vec4<f32>, angle: f32) -> vec4<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec4<f32>(
        c * v.x - s * v.y,
        s * v.x + c * v.y,
        v.z,
        v.w
    );
}

// 4D Mandelbulb-like iteration (quaternion julia variant projected from 4D)
fn julia4D(c4: vec4<f32>, z0: vec4<f32>, maxIter: i32) -> vec2<f32> {
    var z = z0;
    var dz = 1.0;

    for (var i = 0; i < maxIter; i++) {
        let r = length(z);
        if (r > 4.0) {
            return vec2<f32>(f32(i), r);
        }
        // Quaternion squaring: (a,b,c,d)^2 using quaternion algebra
        // z' = z^2 + c, quaternion multiplication
        let a = z.x; let b = z.y; let c = z.z; let d = z.w;
        z = vec4<f32>(
            a*a - b*b - c*c - d*d,
            2.0*a*b,
            2.0*a*c,
            2.0*a*d
        ) + c4;
        dz = 2.0 * r * dz + 1.0;
    }
    return vec2<f32>(f32(maxIter), length(z));
}

// 4D hypercube lattice escape
fn hypercubeFractal(p4: vec4<f32>, t: f32, bass: f32, mids: f32) -> f32 {
    var z = p4;
    let fold = 1.2 + bass * 0.3;

    for (var i = 0; i < 6; i++) {
        // Box fold in 4D
        z = clamp(z, vec4<f32>(-fold), vec4<f32>(fold)) * 2.0 - z;
        // Sphere fold
        let r2 = dot(z, z);
        let minR2 = 0.4 + mids * 0.2;
        let fixedR2 = 1.0;
        if (r2 < minR2) {
            z *= fixedR2 / minR2;
        } else if (r2 < fixedR2) {
            z *= fixedR2 / r2;
        }
        // Scale and offset
        z = z * (1.5 + bass * 0.3) + p4;
    }
    return length(z.xyz) - 1.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let aspect = res.x / res.y;
    let uvA = vec2<f32>((uv.x - 0.5) * aspect, uv.y - 0.5);

    let t = u.config.x;
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let zoomLevel     = u.zoom_params.x * 2.0 + 0.5;   // 0.5..2.5
    let rotSpeed      = u.zoom_params.y * 0.4 + 0.05;   // 0.05..0.45
    let colorShift    = u.zoom_params.z;                 // 0..1
    let detailLevel   = u.zoom_params.w;                 // 0..1

    // Mouse controls the W and extra dimension navigation
    let mousePos = vec2<f32>(u.zoom_config.y - 0.5, u.zoom_config.z - 0.5);
    let w_dim = mousePos.x * PI * 1.5; // extra dimension W from mouse X
    let v_dim = mousePos.y * PI * 1.5; // extra dimension V from mouse Y

    // Scale UV into 4D space
    let xy = uvA / zoomLevel;

    // 4D point: XY from screen, ZW from time and mouse
    var p4 = vec4<f32>(
        xy.x,
        xy.y,
        cos(t * rotSpeed * 0.5 + w_dim) * (0.8 + mids * 0.3),
        sin(t * rotSpeed * 0.4 + v_dim) * (0.8 + bass * 0.3)
    );

    // Apply 4D rotations driven by time and audio
    p4 = rot4XW(p4, t * rotSpeed + bass * 0.5);
    p4 = rot4YZ(p4, t * rotSpeed * 0.7 + mids * 0.3);
    p4 = rot4ZW(p4, t * rotSpeed * 0.5 + treble * 0.4);
    p4 = rot4XY(p4, t * rotSpeed * 0.3);

    // Julia set constant: slowly navigates 4D parameter space
    let juliaC = vec4<f32>(
        -0.1 + sin(t * 0.11 + bass * 0.5) * 0.3,
        0.65 + cos(t * 0.07 + mids * 0.3) * 0.15,
        sin(t * 0.09 + w_dim * 0.5) * 0.2,
        cos(t * 0.13 + v_dim * 0.5) * 0.15
    );

    let maxIter = i32(4.0 + detailLevel * 8.0 + bass * 2.0);
    let juliaResult = julia4D(juliaC, p4, maxIter);
    let juliaIter = juliaResult.x;
    let juliaR    = juliaResult.y;

    // Hypercube fractal for structural detail
    let hypercubeD = hypercubeFractal(p4 * (0.5 + treble * 0.2), t, bass, mids);

    // Coloring: smooth iteration count + exterior distance
    let smoothIter = juliaIter + 1.0 - log2(log2(juliaR + 1.0) + 1.0);
    let normIter = smoothIter / f32(maxIter);

    // Ethereal color palette
    let hueBase = colorShift + normIter * 1.5 + t * 0.03;
    let r = 0.5 + 0.5 * cos(hueBase * TAU + 0.0 + bass * 1.0);
    let g = 0.5 + 0.5 * cos(hueBase * TAU + 2.094 + mids * 0.8);
    let b = 0.5 + 0.5 * cos(hueBase * TAU + 4.189 + treble * 1.2);
    var color = vec3<f32>(r, g, b);

    // Interior: deep dark with inner glow
    if (juliaIter >= f32(maxIter)) {
        let innerGlow = exp(-length(p4) * 2.0) * (0.3 + bass * 0.4);
        color = vec3<f32>(0.05, 0.02, 0.08) + vec3<f32>(0.2, 0.1, 0.5) * innerGlow;
    }

    // Hypercube structural overlay
    let structuralLine = smoothstep(0.05, 0.0, abs(hypercubeD)) * treble * 0.5;
    color += vec3<f32>(0.8, 0.9, 1.0) * structuralLine;

    // Dimensional depth fog: further W/V coordinates are hazier
    let dimFog = 1.0 - exp(-abs(p4.w) * 0.8);
    color = mix(color, vec3<f32>(0.05, 0.03, 0.1), dimFog * 0.4);

    // Edge sharpening: bright boundary between inside/outside
    let boundarySharp = smoothstep(f32(maxIter) - 1.5, f32(maxIter) - 0.5, juliaIter);
    color += vec3<f32>(1.0, 0.95, 0.8) * boundarySharp * 0.5;

    let decay = 0.96;
    let temporal = mix(prev.rgb * decay, color, 0.25);
    textureStore(dataTextureA, global_id.xy, vec4<f32>(temporal, 1.0));

    textureStore(writeTexture, global_id.xy, vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(1.0)), 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
}
