import os
import glob
import re

def upgrade_shader(filepath):
    with open(filepath, 'r') as f:
        original_content = f.read()

    content = original_content

    # 1. Bounded ripples
    if 'cnt: u32' in content and 'fn rippleDisp' in content:
        content = re.sub(r'(fn rippleDisp.*?)cnt:\s*u32(.*?)', r'\1cnt_in: u32\2', content, count=1)
        # Find the for loop over ripples
        content = re.sub(r'(for\s*\(\s*var\s+i\s*:\s*u32\s*=\s*0u;\s*i\s*<\s*cnt;\s*i\+\+\s*\)\s*\{)', 
                         r'let cnt = min(cnt_in, 50u);\n    \1', content, count=1)
    
    # Alternatively, if they directly do `u32(u.config.y)` in rippleDisp
    if 'fn rippleDisp' in content and 'cnt_in: u32' not in content:
        # already handled or no cnt param
        pass

    # 2. ACES tone map definition
    aces_func = """// ─────────────────────────────────────────────────────────────────────────────
// ACES Tone Mapping
// ─────────────────────────────────────────────────────────────────────────────
fn aces_tonemap(color: vec3<f32>) -> vec3<f32> {
    let m1 = mat3x3<f32>(
        0.59719, 0.07600, 0.02840,
        0.35458, 0.90834, 0.13383,
        0.04823, 0.01566, 0.83777
    );
    let m2 = mat3x3<f32>(
        1.60475, -0.10208, -0.00327,
        -0.53108,  1.10813, -0.07276,
        -0.07367, -0.00605,  1.07602
    );
    let v = m1 * color;
    let a = v * (v + 0.0245786) - 0.000090537;
    let b = v * (0.983729 * v + 0.4329510) + 0.238081;
    return clamp(m2 * (a / b), vec3<f32>(0.0), vec3<f32>(1.0));
}"""
    if "aces_tonemap(" not in content:
        # insert before main
        content = re.sub(r'(@compute @workgroup_size)', aces_func + r'\n\n\1', content, count=1)

    # 3. Apply ACES tone map and Semantic Alpha
    # Find the textureStore(writeTexture, ...) line
    # Sometimes it's textureStore(writeTexture, gid.xy, vec4<f32>(outR, outG, outB, finalAlpha))
    # We want to intercept the final RGB.
    
    # 4. exact textureLoad from dataTextureC
    # e.g., textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0) -> textureLoad(dataTextureC, vec2<i32>(uv * vec2<f32>(textureDimensions(dataTextureC))), 0)
    # Actually wait, maybe it's not sampling but we just need to ensure if dataTextureC is used, it's a load.
    
    with open(filepath, 'w') as f:
        f.write(content)

for f in glob.glob("batch58a/*.wgsl"):
    print(f)
    upgrade_shader(f)

