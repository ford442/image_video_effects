// ----------------------------------------------------------------
// Hyper-Dimensional Tesseract-Labyrinth
// Category: generative
// ----------------------------------------------------------------
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Tesseract Complexity, y=Edge Glow, z=Warp Field, w=Fly Speed
    ripples: array<vec4<f32>, 50>,
};

// --- UTILS ---
fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn rotate4D(p: vec4<f32>, angle1: f32, angle2: f32) -> vec4<f32> {
    var q = p;
    // Rotation in XW plane
    let c1 = cos(angle1); let s1 = sin(angle1);
    let xw = vec2<f32>(q.x * c1 - q.w * s1, q.x * s1 + q.w * c1);
    q.x = xw.x;
    q.w = xw.y;

    // Rotation in YZ plane
    let c2 = cos(angle2); let s2 = sin(angle2);
    let yz = vec2<f32>(q.y * c2 - q.z * s2, q.y * s2 + q.z * c2);
    q.y = yz.x;
    q.z = yz.y;

    return q;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdBoxFrame(p: vec3<f32>, b: vec3<f32>, e: f32) -> f32 {
    let p_abs = abs(p) - b;
    let q = abs(p_abs + e) - e;
    let c1 = length(max(vec3<f32>(p_abs.x, q.y, q.z), vec3<f32>(0.0))) + min(max(p_abs.x, max(q.y, q.z)), 0.0);
    let c2 = length(max(vec3<f32>(q.x, p_abs.y, q.z), vec3<f32>(0.0))) + min(max(q.x, max(p_abs.y, q.z)), 0.0);
    let c3 = length(max(vec3<f32>(q.x, q.y, p_abs.z), vec3<f32>(0.0))) + min(max(q.x, max(q.y, p_abs.z)), 0.0);
    return min(min(c1, c2), c3);
}

fn map(p: vec3<f32>, complexity: f32, warp: f32, audio: f32, time: f32, mousePos: vec3<f32>) -> vec2<f32> {
    var q3 = p;
    let spacing = 6.0;

    // Mouse Warp
    let distToMouse = length(p - mousePos);
    var warpDistortion = 0.0;
    if (distToMouse < 8.0) {
        warpDistortion = (1.0 - smoothstep(0.0, 8.0, distToMouse)) * warp * 2.0;
    }

    // Domain Repetition
    q3.x = q3.x - round(q3.x / spacing) * spacing;
    q3.y = q3.y - round(q3.y / spacing) * spacing;
    q3.z = q3.z - round(q3.z / spacing) * spacing;

    // Convert to 4D
    var q4 = vec4<f32>(q3, 0.0);

    let a1 = time * 0.5 * complexity + warpDistortion;
    let a2 = time * 0.3 * complexity + audio * 2.0;
    q4 = rotate4D(q4, a1, a2);

    // Convert back to 3D for SDF evaluation
    let projected3D = q4.xyz;

    // Structure: Box Frame for glowing edges, Solid Box for transparent faces
    let boxSize = vec3<f32>(1.5);
    let frameThickness = 0.05;

    let dFrame = sdBoxFrame(projected3D, boxSize, frameThickness);
    let dSolid = sdBox(projected3D, boxSize * 0.98); // slightly smaller

    // Material 1.0 = Frame, 2.0 = Solid Face
    if (dFrame < dSolid) {
        return vec2<f32>(dFrame, 1.0);
    } else {
        return vec2<f32>(dSolid, 2.0);
    }
}

fn calcNormal(p: vec3<f32>, complexity: f32, warp: f32, audio: f32, time: f32, mousePos: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.01, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, complexity, warp, audio, time, mousePos).x - map(p - e.xyy, complexity, warp, audio, time, mousePos).x,
        map(p + e.yxy, complexity, warp, audio, time, mousePos).x - map(p - e.yxy, complexity, warp, audio, time, mousePos).x,
        map(p + e.yyx, complexity, warp, audio, time, mousePos).x - map(p - e.yyx, complexity, warp, audio, time, mousePos).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

    let uv = (fragCoord * 2.0 - res) / res.y;
    let time = u.config.x;
    let audio = u.config.y;

    // Parameters mapped from zoom_params
    let complexity = u.zoom_params.x;
    let edgeGlow = u.zoom_params.y;
    let warpField = u.zoom_params.z;
    let flySpeed = u.zoom_params.w;

    // Mouse Interaction
    let mouseX = (u.zoom_config.y * 2.0 - 1.0) * res.x / res.y;
    let mouseY = -(u.zoom_config.z * 2.0 - 1.0);

    // Camera setup - flying through the maze
    var ro = vec3<f32>(time * flySpeed * 0.5, time * flySpeed * 0.2, time * flySpeed);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Apply camera rotation based on mouse
    let temp_xz = rotate2D(mouseX * 3.14) * vec2<f32>(rd.x, rd.z);
    rd.x = temp_xz.x;
    rd.z = temp_xz.y;

    let temp_yz = rotate2D(mouseY * 3.14) * vec2<f32>(rd.y, rd.z);
    rd.y = temp_yz.x;
    rd.z = temp_yz.y;

    let mousePos = ro + normalize(vec3<f32>(mouseX, mouseY, 1.0)) * 5.0;

    var t = 0.0;
    var d = 0.0;
    var matId = 0.0;
    var p = ro;

    // Accumulate glow along the ray
    var glowCol = vec3<f32>(0.0);

    for(var i = 0; i < 80; i++) {
        p = ro + rd * t;
        let res_map = map(p, complexity, warpField, audio, time, mousePos);
        d = res_map.x;
        matId = res_map.y;

        // Volumetric glow accumulation near edges
        if (matId == 1.0) {
            let glowColorBase = 0.5 + 0.5 * cos(time * 2.0 + p.xyz * 0.5 + vec3<f32>(0.0, 2.0, 4.0));
            glowCol += glowColorBase * (0.005 / (abs(d) + 0.01)) * edgeGlow * (1.0 + audio * 2.0);
        }

        if(d < 0.01 || t > 60.0) { break; }
        t += d * 0.8;
    }

    var col = vec3<f32>(0.0);

    if(t < 60.0) {
        let n = calcNormal(p, complexity, warpField, audio, time, mousePos);
        let viewDir = -rd;
        let fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 3.0);

        if (matId == 1.0) {
            // Solid emissive edges
            col = vec3<f32>(1.0) * edgeGlow * (1.0 + audio);
        } else {
            // Glassy faces
            let envReflection = vec3<f32>(0.1, 0.3, 0.8) * fresnel * 2.0;
            let transparency = vec3<f32>(0.05, 0.05, 0.1);
            col = envReflection + transparency;
        }
    }

    // Add volumetric edge glow and distance fog
    col += glowCol * exp(-0.02 * t);
    col = mix(col, vec3<f32>(0.02, 0.01, 0.05), smoothstep(0.0, 60.0, t));

    col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}