// ----------------------------------------------------------------
// Prismatic Fractal-Dunes
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
    zoom_params: vec4<f32>,  // x=Dune Complexity, y=Prism Dispersion, z=Geyser Height, w=Wind Speed
    ripples: array<vec4<f32>, 50>,
};

// --- UTILS ---
fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    var mat = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    var pp = p;
    for (var i = 0; i < octaves; i++) {
        v += a * noise(pp);
        pp = mat * pp * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn kifsShard(p: vec3<f32>) -> f32 {
    var pos = p;
    var scale = 1.0;
    for (var i = 0; i < 4; i++) {
        pos = abs(pos) - vec3<f32>(0.1, 0.5, 0.1) * scale;
        let rot1 = rotate2D(1.2);
        let temp_xy = rot1 * pos.xy;
        pos.x = temp_xy.x;
        pos.y = temp_xy.y;
        let rot2 = rotate2D(0.5);
        let temp_xz = rot2 * pos.xz;
        pos.x = temp_xz.x;
        pos.z = temp_xz.y;
        pos *= 1.5;
        scale *= 1.5;
    }
    return sdBox(pos, vec3<f32>(0.2, 1.0, 0.2)) / scale;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

    let uv = (fragCoord * 2.0 - res) / res.y;
    let time = u.config.x;
    let audio = u.config.y;

    // Parameters
    let duneComplexity = u.zoom_params.x;
    let dispersion = u.zoom_params.y;
    let geyserHeight = u.zoom_params.z;
    let windSpeed = u.zoom_params.w;

    // Camera setup
    var ro = vec3<f32>(0.0, 2.0 + audio * 0.5, -5.0 + time * windSpeed * 2.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Slight look down
    let rotX = rotate2D(-0.3);
    let temp_rd_yz = rotX * rd.yz;
    rd.y = temp_rd_yz.x;
    rd.z = temp_rd_yz.y;

    // Mouse Interaction
    let mouseX = (u.zoom_config.y * 2.0 - 1.0) * res.x / res.y;
    let mouseY = -(u.zoom_config.z * 2.0 - 1.0);

    // Project mouse onto ground plane (y=0)
    var mousePos3D = vec3<f32>(1000.0);
    let mouseRay = normalize(vec3<f32>(mouseX, mouseY, 1.0));
    let tMouse = -ro.y / mouseRay.y;
    if (tMouse > 0.0) {
        mousePos3D = ro + mouseRay * tMouse;
    }

    var col = vec3<f32>(0.0);
    var t = 0.0;
    var d = 0.0;
    var glow = vec3<f32>(0.0);

    var hitKifs = false;

    for (var i = 0; i < 120; i++) {
        var p = ro + rd * t;

        // Terrain SDF
        // Domain warping FBM for dunes
        let warp = vec2<f32>(
            fbm(p.xz * 0.1 + vec2<f32>(time * windSpeed * 0.5, 0.0), 3),
            fbm(p.xz * 0.1 - vec2<f32>(0.0, time * windSpeed * 0.5), 3)
        );
        let h = fbm(p.xz * (0.2 + duneComplexity * 0.02) + warp * 2.0, 6) * 2.5;
        var dTerrain = p.y + 1.0 - h;

        // Crater from mouse interaction
        let mouseDist = length(p.xz - mousePos3D.xz);
        if (mouseDist < 4.0) {
            dTerrain = smin(dTerrain, length(p - mousePos3D) - 1.0, 1.5);
        }

        // KIFS Geysers
        var dGeyser = 1000.0;
        // Place geysers on a grid
        let geyserCell = floor(p.xz / 8.0);
        let geyserHash = hash21(geyserCell);
        if (geyserHash > 0.7) {
            var localP = p;
            localP.x = (fract(localP.x / 8.0) - 0.5) * 8.0;
            localP.z = (fract(localP.z / 8.0) - 0.5) * 8.0;

            // Mouse pull for geysers
            let pull = clamp(1.0 - mouseDist / 6.0, 0.0, 1.0);
            localP += normalize(mousePos3D - p) * pull * 2.0;

            localP.y -= h - 1.0 + audio * geyserHeight * 2.0 * geyserHash;

            let rotG = rotate2D(time * 2.0 + geyserHash * 10.0);
            let temp_lp_xz = rotG * localP.xz;
            localP.x = temp_lp_xz.x;
            localP.z = temp_lp_xz.y;

            dGeyser = kifsShard(localP);
        }

        d = min(dTerrain, dGeyser);

        if (d < 0.001) {
            if (d == dGeyser) {
                hitKifs = true;
            }
            break;
        }

        glow += vec3<f32>(0.1, 0.5, 0.8) * 0.01 / (abs(dGeyser) + 0.1) * audio;
        t += d * 0.6;
        if (t > 50.0) { break; }
    }

    if (t < 50.0) {
        var p = ro + rd * t;

        // Calculate normal
        let e = vec2<f32>(0.01, 0.0);
        var n = vec3<f32>(0.0);

        if (!hitKifs) {
            let warp = vec2<f32>(fbm(p.xz * 0.1 + vec2<f32>(time * windSpeed * 0.5, 0.0), 3), fbm(p.xz * 0.1 - vec2<f32>(0.0, time * windSpeed * 0.5), 3));
            let h_p = p.y + 1.0 - fbm(p.xz * (0.2 + duneComplexity * 0.02) + warp * 2.0, 6) * 2.5;

            let px = p + e.xyy;
            let warp_x = vec2<f32>(fbm(px.xz * 0.1 + vec2<f32>(time * windSpeed * 0.5, 0.0), 3), fbm(px.xz * 0.1 - vec2<f32>(0.0, time * windSpeed * 0.5), 3));
            let h_px = px.y + 1.0 - fbm(px.xz * (0.2 + duneComplexity * 0.02) + warp_x * 2.0, 6) * 2.5;

            let pz = p + e.yyx;
            let warp_z = vec2<f32>(fbm(pz.xz * 0.1 + vec2<f32>(time * windSpeed * 0.5, 0.0), 3), fbm(pz.xz * 0.1 - vec2<f32>(0.0, time * windSpeed * 0.5), 3));
            let h_pz = pz.y + 1.0 - fbm(pz.xz * (0.2 + duneComplexity * 0.02) + warp_z * 2.0, 6) * 2.5;

            n = normalize(vec3<f32>(h_px - h_p, 0.01, h_pz - h_p));
            // Apply crater normal mod if close to mouse
            let mouseDist = length(p.xz - mousePos3D.xz);
            if (mouseDist < 4.0) {
                 n = normalize(mix(n, normalize(p - mousePos3D), 0.5 * clamp(1.0 - mouseDist/4.0, 0.0, 1.0)));
            }

            // Shading for prismatic sand
            let sunDir = normalize(vec3<f32>(0.5, 0.8, 0.2));
            let sunDir2 = normalize(vec3<f32>(-0.8, 0.4, -0.2));

            let diff1 = max(dot(n, sunDir), 0.0);
            let diff2 = max(dot(n, sunDir2), 0.0);

            // Fresnel / Prism effect
            let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

            // Chromatic dispersion pseudo-effect based on normal and view angle
            let rDisp = dot(n, sunDir) * dispersion;
            let gDisp = dot(n, normalize(sunDir + vec3<f32>(0.1, 0.0, 0.0))) * dispersion;
            let bDisp = dot(n, normalize(sunDir + vec3<f32>(0.2, 0.0, 0.0))) * dispersion;

            var sandBase = vec3<f32>(0.9, 0.7, 0.5);
            let ridgeGlow = smoothstep(0.7, 1.0, fbm(p.xz * 0.5, 3)) * audio; // Cosmic wind ribbons

            col = sandBase * (diff1 * vec3<f32>(1.0, 0.8, 0.6) + diff2 * vec3<f32>(0.4, 0.2, 0.8));
            col += vec3<f32>(rDisp, gDisp, bDisp) * fresnel * 0.5;
            col += vec3<f32>(0.2, 0.8, 1.0) * ridgeGlow;

        } else {
            // Geyser / Crystal shading
            n = normalize(p); // simplified normal for KIFS
            let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 2.0);
            col = vec3<f32>(0.1, 0.8, 1.0) * fresnel * (1.0 + audio * 2.0);
        }

        // Fog
        col = mix(col, vec3<f32>(0.05, 0.05, 0.1), 1.0 - exp(-0.02 * t));
    } else {
        // Sky
        col = vec3<f32>(0.05, 0.05, 0.1) * max(0.0, uv.y + 0.5);
    }

    col += glow;

    col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}