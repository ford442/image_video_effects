import re

with open('public/shaders/gen-chromatic-oracle-jelly.wgsl', 'r') as f:
    code = f.read()

bad = "let synapseSparks = tentacles * step(0.99, sparkHash) * (1.0 + treble * 2.0);"
good = "let synapseSparks = tentacles * step(0.99, sparkHash) * (1.0 + audio.z * 2.0);"
code = code.replace(bad, good)

with open('public/shaders/gen-chromatic-oracle-jelly.wgsl', 'w') as f:
    f.write(code)

