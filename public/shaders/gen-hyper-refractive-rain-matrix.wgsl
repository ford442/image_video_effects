// ----------------------------------------------------------------
// Hyper-Refractive Rain-Matrix
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // mapped to UI sliders
    ripples: array<vec4<f32>, 50>,
};

// --- UTILS ---
fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(vec2<f32>(c, -s), vec2<f32>(s, c));
}

fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += vec3<f32>(dot(p3, p3.yxz + vec3<f32>(33.33)));
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// --- SDFs ---
fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// --- MAIN ALGORITHM ---
fn map(pos_in: vec3<f32>) -> vec2<f32> {
    var p = pos_in;

    let rainDensity = u.zoom_params.x;
    let dropSpeed = u.zoom_params.y;
    let fluidViscosity = u.zoom_params.z;
    let audioReactive = u.config.y;

    let t = u.config.x * dropSpeed * (1.0 + audioReactive * 0.5);
    p.y -= t * 5.0; // Falling motion

    // Mouse Interaction (repel)
    let mousePos = vec2<f32>((u.zoom_config.y - 0.5) * 20.0, -(u.zoom_config.z - 0.5) * 20.0);
    let dMouse = length(p.xz - mousePos);
    if (dMouse < 5.0) {
        let repelForce = (5.0 - dMouse) * 0.5;
        let dir = normalize(p.xz - mousePos);
        p.x += dir.x * repelForce;
        p.z += dir.y * repelForce;
    }

    // Domain repetition
    let cellSpacing = 4.0 / rainDensity;
    let cell = floor(p / cellSpacing);
    var q = p - cell * cellSpacing - cellSpacing * 0.5;

    let h = hash33(cell);
    q.y += (h.y - 0.5) * cellSpacing; // random offset

    // Stretched drops
    let stretch = 1.0 + dropSpeed + audioReactive;
    let d1 = sdCapsule(q, vec3<f32>(0.0, stretch, 0.0), vec3<f32>(0.0, -stretch, 0.0), 0.2 + h.x * 0.3);

    // Neighbor drops for merging
    var d2 = 1e10;
    for(var i=-1; i<=1; i++) {
        for(var j=-1; j<=1; j++) {
            if (i==0 && j==0) { continue; }
            let ncell = cell + vec3<f32>(f32(i), 0.0, f32(j));
            let nh = hash33(ncell);
            var nq = p - ncell * cellSpacing - cellSpacing * 0.5;
            nq.y += (nh.y - 0.5) * cellSpacing;
            let nd = sdCapsule(nq, vec3<f32>(0.0, stretch, 0.0), vec3<f32>(0.0, -stretch, 0.0), 0.2 + nh.x * 0.3);
            d2 = smin(d2, nd, fluidViscosity * 1.5 + 0.1);
        }
    }

    let dFinal = smin(d1, d2, fluidViscosity * 1.5 + 0.1);

    return vec2<f32>(dFinal, 1.0); // Material ID 1
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize(
        e.xyy * map(p + e.xyy).x +
        e.yyx * map(p + e.yyx).x +
        e.yxy * map(p + e.yxy).x +
        e.xxx * map(p + e.xxx).x
    );
}

fn render(ro: vec3<f32>, rd: vec3<f32>) -> vec3<f32> {
    var col = vec3<f32>(0.0);
    var t = 0.0;
    var m = -1.0;

    for(var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p);
        if (res.x < 0.001) {
            m = res.y;
            break;
        }
        if (t > 50.0) {
            break;
        }
        t += res.x * 0.8; // conservative step
    }

    let stormIntensity = u.zoom_params.w;
    let bgCol = mix(vec3<f32>(0.02, 0.05, 0.1), vec3<f32>(0.1, 0.4, 0.6), rd.y * 0.5 + 0.5) * stormIntensity;
    col = bgCol;

    if (m > 0.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        // Pseudo-refraction
        let refDir = refract(rd, n, 0.8);
        let hRef = hash33(refDir * 10.0 + u.config.x);
        let refCol = mix(vec3<f32>(0.05, 0.1, 0.2), vec3<f32>(0.2, 0.8, 1.0), hRef.x) * stormIntensity;

        // Lighting
        let lig = normalize(vec3<f32>(0.5, 0.8, 0.3));
        let hal = normalize(lig - rd);
        let dif = clamp(dot(n, lig), 0.0, 1.0);
        let spe = pow(clamp(dot(n, hal), 0.0, 1.0), 32.0);

        col = mix(refCol, vec3<f32>(1.0), spe + dif * 0.2);

        // Fog
        col = mix(col, bgCol, 1.0 - exp(-0.02 * t * t));
    }

    return col;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));

    if (fragCoord.x >= dimensions.x || fragCoord.y >= dimensions.y) {
        return;
    }

    let uv = (fragCoord - 0.5 * dimensions) / dimensions.y;

    var ro = vec3<f32>(0.0, 5.0, 10.0);
    var rd = normalize(vec3<f32>(uv, -1.0));

    let rotY = rotate2D(u.config.x * 0.1);
    let roXZ = rotY * vec2<f32>(ro.x, ro.z);
    ro.x = roXZ.x;
    ro.z = roXZ.y;
    let rdXZ = rotY * vec2<f32>(rd.x, rd.z);
    rd.x = rdXZ.x;
    rd.z = rdXZ.y;

    let col = render(ro, rd);

    let finalCol = vec4<f32>(col, 1.0);
    textureStore(writeTexture, vec2<i32>(id.xy), finalCol);
}