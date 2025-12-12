// ---------------------------------------------------------------
//  Stellar Orbit - Compute Shader Version
// ---------------------------------------------------------------

// 1. UNIFORMS & BINDINGS
// Adjust these binding numbers to match your specific JS setup if needed.
// Based on your first prompt, I assumed:
// Binding 2: Output Texture
// Binding 3: Uniforms

struct Uniforms {
    iResolution : vec4<f32>, // xy = width/height
    iTime       : f32,
    iFrame      : f32,
    padding     : vec2<f32>, // Padding for alignment
};

@group(0) @binding(2) var outTex : texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u : Uniforms;

// Global private variables for the accumulation logic
var<private> g1 : f32;
var<private> g2 : f32;
var<private> g3 : f32;

// Constants
const x_379 = vec3<f32>(0.57735025882720947266, 0.57735025882720947266, -0.57735025882720947266);

// ---------------------------------------------------------------
//  MATH & RAYMARCHING FUNCTIONS
// ---------------------------------------------------------------

fn rot_vf3_vf3_f1_(p_1 : ptr<function, vec3<f32>>, a : ptr<function, vec3<f32>>, t : ptr<function, f32>) {
    let u_2 = cross(*(a), *(p_1));
    let v = cross(*(a), u_2);
    *(p_1) = u_2 * sin(*(t)) + v * cos(*(t)) + *(a) * dot(*(a), *(p_1));
}

fn lookAt_vf3_vf3_vf3_vf3_(rd : ptr<function, vec3<f32>>, ro : ptr<function, vec3<f32>>, ta : ptr<function, vec3<f32>>, up : ptr<function, vec3<f32>>) {
    let w = normalize(*(ta) - *(ro));
    let u = normalize(cross(w, *(up)));
    let v = cross(u, w);
    *(rd) = normalize(u * (*rd).x + v * (*rd).y + w * (*rd).z);
}

fn sFold45_vf2_(p_3 : ptr<function, vec2<f32>>) {
    let v_2 = vec2<f32>(0.70710678, -0.70710678);
    let g_1 = dot(*(p_3), v_2);
    *(p_3) = *(p_3) - v_2 * (g_1 - sqrt(g_1 * g_1 + 0.00005));
}

fn stella_vf3_f1_(p_4 : ptr<function, vec3<f32>>, s_1 : ptr<function, f32>) -> f32 {
    *(p_4) = sqrt((*(p_4) * *(p_4)) + 0.00005);
    var param_4 = vec2<f32>((*p_4).x, (*p_4).z);
    sFold45_vf2_(&param_4);
    *(p_4) = vec3<f32>(param_4.x, (*p_4).y, param_4.y);
    var param_5 = vec2<f32>((*p_4).y, (*p_4).z);
    sFold45_vf2_(&param_5);
    *(p_4) = vec3<f32>((*p_4).x, param_5.x, param_5.y);
    return dot(*(p_4), x_379) - *(s_1);
}

fn stellas_vf3_(p_5 : ptr<function, vec3<f32>>) -> f32 {
    (*p_5).y = (*p_5).y + u.iTime;
    let c = 2.0;
    var e = floor(*(p_5) / c);
    e = sin(((e * 2.5 + vec3<f32>(e.y, e.z, e.x) * 3.0) + 1.345) * 11.0);
    *(p_5) = *(p_5) - e * 0.5;
    *(p_5) = (*(p_5) - c * floor(*(p_5) / c)) - c * 0.5;
    
    var param_6 = *(p_5);
    var param_7 = fract(sin(e + 2060303.5)) - 0.5;
    var param_8 = u.iTime * 1.5;
    rot_vf3_vf3_f1_(&param_6, &param_7, &param_8);
    *(p_5) = param_6;
    
    var param_9 = *(p_5);
    var param_10 = 0.08;
    return min(0.7, stella_vf3_f1_(&param_9, &param_10));
}

fn pointAt_vf3_vf3_vf3_(p : ptr<function, vec3<f32>>, dir : ptr<function, vec3<f32>>, up_1 : ptr<function, vec3<f32>>) {
    let u_1 = normalize(cross(*(dir), *(up_1)));
    let v_1 = cross(u_1, *(dir));
    *(p) = vec3<f32>(dot(*(p), u_1), dot(*(p), v_1), dot(*(p), *(dir)));
}

fn pSFold_vf2_f1_(p_2 : ptr<function, vec2<f32>>, n : ptr<function, f32>) {
    let h_1 = floor(log2(*(n)));
    var a_2 = (6.283185 / *(n)) * exp2(h_1);
    for(var i = 0.0; i < h_1 + 2.0; i = i + 1.0) {
        let v_1 = vec2<f32>(-cos(a_2), sin(a_2));
        let g = dot(*(p_2), v_1);
        *(p_2) = *(p_2) - v_1 * (g - sqrt(g * g + 0.002));
        a_2 = a_2 * 0.5;
    }
}

fn structure_vf3_(p_6 : ptr<function, vec3<f32>>) -> f32 {
    var d = 1000.0;
    var q = *(p_6);
    
    for(var i_2 = 0; i_2 < 12; i_2 = i_2 + 1) {
        var w_1 = vec3<f32>(0.8506508, 0.5257311, 0.0);
        let bit1 = f32((i_2 >> 1u) & 1);
        let bit0 = f32(i_2 & 1);
        let xy = w_1.xy * (vec2<f32>(bit1, bit0) * 2.0 - 1.0);
        w_1 = vec3<f32>(xy.x, xy.y, w_1.z);
        
        if ((i_2 % 3) == 1) { w_1 = w_1.yzx; }
        if ((i_2 % 3) == 2) { w_1 = w_1.zxy; }
        
        var param_11 = q;
        var param_12 = w_1;
        var param_13 = sign(w_1.z) * -sign(w_1.x + w_1.y + w_1.z) * w_1.zxy;
        pointAt_vf3_vf3_vf3_(&param_11, &param_12, &param_13);
        q = param_11;
        
        let d0 = length(q - vec3<f32>(0.0, 0.0, clamp(q.z, 2.0, 8.0))) - 0.4 + q.z * 0.05;
        d = min(d, d0);
        g2 += 0.1 / (0.1 + d0 * d0);
        
        let c_1 = 0.8;
        let e_1 = floor(q.z / c_1 - c_1 * 0.5);
        q.z -= c_1 * clamp(round(q.z / c_1), 3.0, 9.0);
        q.z -= clamp(q.z, -0.05, 0.05);
        
        var param_14 = q.xy;
        var param_15 = 5.0;
        pSFold_vf2_f1_(&param_14, &param_15);
        q = vec3<f32>(param_14.x, param_14.y, q.z);
        
        q.y -= (1.4 - e_1 * 0.2) + sin(u.iTime * 10.0 + e_1 + f32(i_2)) * 0.05;
        q.x -= clamp(q.x, -2.0, 2.0);
        q.y -= clamp(q.y, 0.0, 0.2);
        
        let d1 = length(q) * 0.7 - 0.05;
        d = min(d, d1);
        
        if (e_1 == (2.0 + floor(u.iTime * 5.0 - 7.0 * floor(u.iTime * 5.0 / 7.0)))) {
             g1 += 0.1 / (0.1 + d1 * d1);
        }
    }
    return d;
}

fn randVec_f1_(s : ptr<function, f32>) -> vec3<f32> {
    let n_3 = fract(sin(vec2<f32>(*(s), *(s) + 215.3)) * 12345.5);
    return vec3<f32>(cos(n_3.y)*cos(n_3.x), sin(n_3.y), cos(n_3.y)*sin(n_3.x));
}

fn randCurve_f1_f1_(t_1 : ptr<function, f32>, n_1 : ptr<function, f32>) -> vec3<f32> {
    var p_11 = vec3<f32>(0.0);
    for(var i_1 = 0; i_1 < 3; i_1 = i_1 + 1) {
        *n_1 = *n_1 + 365.0;
        var param = *n_1;
        let r = randVec_f1_(&param);
        *t_1 = *t_1 * 1.3;
        p_11 = p_11 + r * sin(*t_1 + sin(*t_1 * 0.6) * 0.5);
    }
    return p_11;
}

fn rabbit_vf3_(p_7 : ptr<function, vec3<f32>>) -> f32 {
    var param_16 = u.iTime;
    var param_17 = 2576.0;
    let offset = randCurve_f1_f1_(&param_16, &param_17) * 5.0;
    *p_7 = *p_7 - offset;
    
    var param_18 = *p_7;
    var param_19 = vec3<f32>(1.0);
    var param_20 = u.iTime;
    rot_vf3_vf3_f1_(&param_18, &param_19, &param_20);
    *p_7 = param_18;
    
    var param_21 = *p_7;
    var param_22 = 0.2;
    let d_1 = stella_vf3_f1_(&param_21, &param_22);
    g3 += 0.1 / (0.1 + d_1 * d_1);
    return d_1;
}

fn map_vf3_(p_8 : ptr<function, vec3<f32>>) -> f32 {
    var param_23 = *p_8;
    let d1 = stellas_vf3_(&param_23);
    var param_24 = *p_8;
    let d2 = structure_vf3_(&param_24);
    var param_25 = *p_8;
    let d3 = rabbit_vf3_(&param_25);
    return min(min(d1, d2), d3);
}

fn calcNormal_vf3_(p_9 : ptr<function, vec3<f32>>) -> vec3<f32> {
    var n_4 = vec3<f32>(0.0);
    for(var i_3 = 0; i_3 < 4; i_3 = i_3 + 1) {
        let e_2 = (vec3<f32>(f32((9 >> u32(i_3)) & 1), f32((i_3 >> 1) & 1), f32(i_3 & 1)) * 2.0 - 1.0) * 0.001;
        var param_26 = *p_9 + e_2;
        n_4 += e_2 * map_vf3_(&param_26);
    }
    return normalize(n_4);
}

fn doColor_vf3_(p_10 : ptr<function, vec3<f32>>) -> vec3<f32> {
    var param_27 = *p_10;
    if (stellas_vf3_(&param_27) < 0.001) {
        return vec3<f32>(0.7, 0.7, 1.0);
    }
    return vec3<f32>(1.0);
}

fn orbit_f1_f1_(t_2 : ptr<function, f32>, n_2 : ptr<function, f32>) -> vec3<f32> {
    var param_1 = -(*t_2) * 1.5 + u.iTime;
    var param_2 = 2576.0;
    let p_12 = randCurve_f1_f1_(&param_1, &param_2) * 5.0;
    
    var param_3 = *n_2;
    let off = randVec_f1_(&param_3) * (*t_2 + 0.05) * 0.6;
    let time = u.iTime + fract(sin(*n_2 * 12345.5)) * 5.0;
    return p_12 + off * sin(time + 0.5 * sin(0.5 * time));
}

fn cLine_vf3_vf3_vf3_vf3_(ro_1 : ptr<function, vec3<f32>>, rd_1 : ptr<function, vec3<f32>>, a_1 : ptr<function, vec3<f32>>, b : ptr<function, vec3<f32>>) -> vec3<f32> {
    let ab = normalize(*b - *a_1);
    let ao = *a_1 - *ro_1;
    let d0 = dot(*rd_1, ab);
    let d1 = dot(*rd_1, ao);
    let d2 = dot(ab, ao);
    let t = clamp((d0 * d1 - d2) / (1.0 - d0 * d0) / length(*b - *a_1), 0.0, 1.0);
    
    let p = *a_1 + (*b - *a_1) * t - *ro_1;
    return vec3<f32>(length(cross(p, *rd_1)), dot(p, *rd_1), t);
}

fn hue_f1_(h : ptr<function, f32>) -> vec3<f32> {
    return cos((vec3<f32>(0.0, 0.66, -0.66) + *h) * 0.785 * 8.0) * 0.5 + 0.5;
}

// ---------------------------------------------------------------
//  MAIN COMPUTE LOGIC
// ---------------------------------------------------------------

fn mainImage(fragColor : ptr<function, vec4<f32>>, fragCoord : vec2<f32>) {
    // Re-mapped coordinate calculation for Compute
    var p = (fragCoord * 2.0 - u.iResolution.xy) / u.iResolution.y;
    
    var col = vec3<f32>(0.0, 0.0, 0.05);
    
    // Camera logic
    let camIndices = array<i32, 4>(7, 10, 12, 15);
    let idx = camIndices[i32(abs(4.0 * sin(u.iTime * 0.3 + 3.0 * sin(u.iTime * 0.2)))) % 4];
    var ro = vec3<f32>(1.0, 0.0, f32(idx));
    
    var param_28 = ro;
    var param_29 = vec3<f32>(1.0);
    var param_30 = u.iTime * 0.2;
    rot_vf3_vf3_f1_(&param_28, &param_29, &param_30);
    ro = param_28;
    
    var ta = vec3<f32>(2.0, 1.0, 2.0);
    var rd = normalize(vec3<f32>(p.x, p.y, 2.0));
    
    var param_31 = rd;
    var param_32 = ro;
    var param_33 = ta;
    var param_34 = vec3<f32>(0.0, 1.0, 0.0);
    lookAt_vf3_vf3_vf3_vf3_(&param_31, &param_32, &param_33, &param_34);
    rd = param_31;
    
    // Raymarching
    var z = 0.0;
    var d = 0.0;
    var i = 0.0;
    for(i = 0.0; i < 50.0; i = i + 1.0) {
        var param_35 = ro + rd * z;
        d = map_vf3_(&param_35);
        z += d;
        if (d < 0.001 || z > 30.0) { break; }
    }
    
    if (d < 0.001) {
        let p_pos = ro + rd * z;
        var param_36 = p_pos;
        let nor = calcNormal_vf3_(&param_36);
        var param_37 = p_pos;
        col = doColor_vf3_(&param_37);
        
        col = col * pow(1.0 - i / 50.0, 2.0);
        col = col * clamp(dot(nor, x_379), 0.3, 1.0);
        col = col * max(0.5 + 0.5 * nor.y, 0.2);
        
        col = col + vec3<f32>(0.8, 0.1, 0.0) * pow(clamp(dot(reflect(normalize(p_pos - ro), nor), vec3<f32>(-0.57)), 0.0, 1.0), 30.0);
        col = col + vec3<f32>(0.1, 0.2, 0.5) * pow(clamp(dot(reflect(normalize(p_pos - ro), nor), x_379), 0.0, 1.0), 30.0);
        
        let fog = exp(-z * z * 0.00001);
        col = mix(vec3<f32>(0.0), col, vec3<f32>(fog));
    }
    
    // Add glow
    col += vec3<f32>(0.9, 0.1, 0.0) * g1 * 0.05;
    col += vec3<f32>(0.0, 0.3, 0.7) * g2 * 0.08;
    col += vec3<f32>(0.5, 0.3, 0.1) * g3 * 0.15;
    
    // Orbit lines loop
    var de = vec3<f32>(10000000.0);
    for(var i_5 = 0.0; i_5 < 1.0; i_5 = i_5 + 0.1428) {
       de = vec3<f32>(10000000.0);
       let off_1 = fract(sin(i_5 * 234.6 + 3160448.0));
       for(var j = 0.0; j < 1.0; j = j + 0.025) { 
           let t_4 = j + off_1 * 0.5;
           var param_38 = t_4; var param_39 = off_1;
           let p1 = orbit_f1_f1_(&param_38, &param_39);
           var param_40 = t_4 + 0.025; var param_41 = off_1;
           let p2 = orbit_f1_f1_(&param_40, &param_41);
           
           var pr1 = ro; var pr2 = rd; var pr3 = p1; var pr4 = p2;
           let c_res = cLine_vf3_vf3_vf3_vf3_(&pr1, &pr2, &pr3, &pr4);
           
           if(de.x * de.y * de.z > c_res.x * c_res.y * c_res.z) {
               de = c_res;
               de.z = j + c_res.z / 40.0;
           }
       }
       
       let s_2 = pow(max(0.0, 0.6 - de.z), 2.0) * 0.1;
       var cond = de.y > 0.0;
       if (cond) { cond = z > de.y; }
       
       if (cond) {
           var param_46 = i_5;
           let hcol = hue_f1_(&param_46);
           col += mix(vec3<f32>(1.0), hcol, vec3<f32>(0.8)) * (1.0 - de.z * 0.9) * smoothstep(s_2 + 0.17, s_2, de.x) * 0.7;
       }
    }
    
    // Gamma / Tone mapping
    let gamma = 0.8 + 0.3 * sin(u.iTime * 0.5 + 3.0 * sin(u.iTime * 0.3));
    col = pow(col, vec3<f32>(gamma));
    
    *fragColor = vec4<f32>(col, 1.0);
}


@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid : vec3<u32>) {
    // 1. Guard check: Ensure we don't write outside texture dimensions
    let dims = vec2<u32>(u.iResolution.xy);
    if (gid.x >= dims.x || gid.y >= dims.y) {
        return;
    }

    // 2. Initialize globals
    g1 = 0.0; g2 = 0.0; g3 = 0.0;
    
    // 3. Prepare Logic inputs
    var outColor : vec4<f32>;
    let coord = vec2<f32>(f32(gid.x), f32(gid.y)); // equivalent to fragCoord
    
    // 4. Run Logic
    mainImage(&outColor, coord);
    
    // 5. Write to Storage Texture
    textureStore(outTex, gid.xy, outColor);
}
