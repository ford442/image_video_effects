// ----------------------------------------------------------------
// Kinetic Neo-Brutalist Megastructure
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
    zoom_params: vec4<f32>,  // x=Block Density, y=Repulsion Radius, z=Neon Intensity, w=Travel Speed
    ripples: array<vec4<f32>, 50>,
};

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn distributionGGX(N: vec3<f32>, H: vec3<f32>, roughness: f32) -> f32 {
    let a = roughness * roughness;
    let a2 = a * a;
    let NdotH = max(dot(N, H), 0.0);
    let NdotH2 = NdotH * NdotH;
    let denom = NdotH2 * (a2 - 1.0) + 1.0;
    return a2 / (3.14159265 * denom * denom);
}

fn fresnelSchlick(cosTheta: f32, F0: vec3<f32>) -> vec3<f32> {
    let ct = clamp(1.0 - cosTheta, 0.0, 1.0);
    let ct5 = ct * ct * ct * ct * ct;
    return F0 + (vec3<f32>(1.0) - F0) * ct5;
}

fn geometrySmith(N: vec3<f32>, V: vec3<f32>, L: vec3<f32>, roughness: f32) -> f32 {
    let NdotV = max(dot(N, V), 0.0);
    let NdotL = max(dot(N, L), 0.0);
    let ggx1 = NdotV / (NdotV * (1.0 - roughness) + roughness);
    let ggx2 = NdotL / (NdotL * (1.0 - roughness) + roughness);
    return ggx1 * ggx2;
}

fn hash13(p3: vec3<f32>) -> f32 {
    var p3_mod = fract(p3 * 0.1031);
    p3_mod += dot(p3_mod, p3_mod.yzx + 33.33);
    return fract((p3_mod.x + p3_mod.y) * p3_mod.z);
}

fn getBuildingParams(id: vec3<f32>) -> vec4<f32> {
    let h = hash13(id);
    let height = 1.0 + h * 3.5;
    let roughness = 0.2 + h * 0.6;
    let neon = step(0.7, h);
    let btype = floor(h * 4.0);
    return vec4<f32>(height, roughness, neon, btype);
}

fn volumetricFog(ro: vec3<f32>, rd: vec3<f32>, tMax: f32) -> vec4<f32> {
    let fogDensity = 0.08;
    let transmittance = exp(-fogDensity * tMax);
    let fogColor = vec3<f32>(0.05, 0.06, 0.08);
    return vec4<f32>(fogColor * (1.0 - transmittance), transmittance);
}

fn map(p: vec3<f32>) -> vec2<f32> {
    var pos = p;
    pos.x += sin(u.config.x * 0.5 + u.config.y) * 2.0;
    let spacing = 4.0;
    var cell = floor(pos / spacing);
    pos = pos - spacing * round(pos / spacing);
    let params = getBuildingParams(cell);
    let h = params.x;
    let rough = params.y;
    let neon = params.z;
    let btype = params.w;
    var d = 1000.0;
    if (btype < 1.0) {
        d = sdBox(pos, vec3<f32>(1.5, h, 1.5));
    } else if (btype < 2.0) {
        let b1 = sdBox(pos, vec3<f32>(1.5, h, 1.5));
        let b2 = sdBox(pos, vec3<f32>(1.6, 0.5, 0.5));
        d = max(b1, -b2);
    } else if (btype < 3.0) {
        let b1 = sdBox(pos, vec3<f32>(1.2, h * 0.8, 1.2));
        let b2 = sdBox(pos - vec3<f32>(0.0, h * 0.5, 0.0), vec3<f32>(1.5, 0.8, 1.5));
        d = smin(b1, b2, 0.5);
    } else {
        let b1 = sdBox(pos, vec3<f32>(1.5, h, 1.5));
        let b2 = sdBox(pos - vec3<f32>(1.0, h * 0.3, 0.0), vec3<f32>(0.8, h * 0.6, 0.8));
        d = smin(b1, b2, 0.6);
    }
    let mouseX = (u.zoom_config.y * 2.0 - 1.0) * 10.0;
    let mouseY = -(u.zoom_config.z * 2.0 - 1.0) * 10.0;
    let mouse_pos = vec3<f32>(mouseX, mouseY, 5.0);
    let dist_to_mouse = length(p - mouse_pos);
    if (dist_to_mouse < u.zoom_params.y) {
        d += (u.zoom_params.y - dist_to_mouse) * 0.5;
    }
    return vec2<f32>(d, hash13(cell) + neon * 10.0);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize(e.xyy * map(p + e.xyy).x +
                     e.yyx * map(p + e.yyx).x +
                     e.yxy * map(p + e.yxy).x +
                     e.xxx * map(p + e.xxx).x);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let dims = vec2<i32>(i32(u.config.z), i32(u.config.w));
    if (coords.x >= dims.x || coords.y >= dims.y) { return; }
    let uv = (vec2<f32>(coords) - 0.5 * vec2<f32>(dims)) / f32(dims.y);
    let ro = vec3<f32>(0.0, 0.0, -10.0 + u.config.x * u.zoom_params.w);
    let rd = normalize(vec3<f32>(uv, 1.0));
    var t = 0.0;
    var mat_id = 0.0;
    for(var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p);
        if (res.x < 0.001 || t > 50.0) {
            mat_id = res.y;
            break;
        }
        t += res.x;
    }
    var col = vec3<f32>(0.01);
    var alpha = 0.0;
    if (t < 50.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let V = -rd;
        let L = normalize(vec3<f32>(0.8, 0.7, -0.6));
        let H = normalize(V + L);
        let params = getBuildingParams(floor(p / 4.0));
        let roughness = params.y;
        let neon = params.z;
        let NdotL = max(dot(n, L), 0.0);
        let F0 = vec3<f32>(0.04);
        let F = fresnelSchlick(max(dot(H, V), 0.0), F0);
        let D = distributionGGX(n, H, roughness);
        let G = geometrySmith(n, V, L, roughness);
        let numerator = D * G * F;
        let denominator = 4.0 * max(dot(n, V), 0.0) * NdotL + 0.001;
        let specular = numerator / denominator;
        let diffuse = vec3<f32>(0.3, 0.32, 0.35) * NdotL * (vec3<f32>(1.0) - F);
        let baseColor = diffuse + specular;
        let neonCol = vec3<f32>(0.0, 1.0, 0.8) * step(0.5, neon) * (0.5 + 0.5 * sin(u.config.y * 10.0));
        col = baseColor * u.zoom_params.x + neonCol * u.zoom_params.z;
        let fog = volumetricFog(ro, rd, t);
        col = col * fog.a + fog.rgb;
        alpha = mat_id;
    }
    let uv01 = vec2<f32>(coords) / vec2<f32>(dims);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv01, 0.0).r;
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(writeTexture, coords, vec4<f32>(col, alpha));
}
