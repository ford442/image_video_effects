import re

with open('public/shaders/gen-chrono-kitsune-prism-weaver.wgsl', 'r') as f:
    code = f.read()

bad = "orbP = vec3<f32>(orbRot.x * orbP.x - orbRot.y * orbP.z, orbP.y, orbRot.y * orbP.x + orbRot.x * orbP.z);"
good = "let rotatedOrb = orbRot * orbP.xz;\norbP = vec3<f32>(rotatedOrb.x, orbP.y, rotatedOrb.y);"
code = code.replace(bad, good)

with open('public/shaders/gen-chrono-kitsune-prism-weaver.wgsl', 'w') as f:
    f.write(code)

