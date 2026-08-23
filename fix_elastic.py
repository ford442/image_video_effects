import re

with open("batch58a/elastic-chromatic.wgsl", 'r') as f:
    content = f.read()

# Replace extraBuffer 0,1,2,3 with 133,134,135,136
content = content.replace("extraBuffer[0]", "extraBuffer[133]")
content = content.replace("extraBuffer[1]", "extraBuffer[134]")
content = content.replace("extraBuffer[2]", "extraBuffer[135]")
content = content.replace("extraBuffer[3]", "extraBuffer[136]")

# Remove shockwave single logic and replace with u.ripples
# Find: var shockOrigin ... let ring = shockwaveRing(uv01, shockOrigin, aspect, time - shockTime, shockBoost);
# Replace with sum over ripples
replace_pattern = r"var shockOrigin = vec2<f32>\(extraBuffer\[4\], extraBuffer\[5\]\);[\s\S]*?let ring = shockwaveRing\(uv01, shockOrigin, aspect, time - shockTime, shockBoost\);"
replacement = """var ring = 0.0;
    let rippleCnt = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCnt; i++) {
        let r = u.ripples[i];
        let age = time - r.z;
        if (age >= 0.0 && age < 4.0) {
            ring += shockwaveRing(uv01, r.xy, aspect, age, shockBoost);
        }
    }"""
content = re.sub(replace_pattern, replacement, content)

with open("batch58a/elastic-chromatic.wgsl", "w") as f:
    f.write(content)
