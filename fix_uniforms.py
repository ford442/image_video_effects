import re

with open("batch58a/chromatic-infection.wgsl", 'r') as f:
    content = f.read()

# Swap zoom_params and zoom_config
content = re.sub(
    r'zoom_params: vec4<f32>,(.*?)zoom_config: vec4<f32>,(.*?)$',
    r'zoom_config: vec4<f32>,\2zoom_params: vec4<f32>,\1',
    content, flags=re.MULTILINE
)

# Wait, simple string replacement is safer
content = content.replace("  zoom_params: vec4<f32>,       // x=spreadSpeed, y=intensity, z=satThresh, w=tendrilScale\n  zoom_config: vec4<f32>,       // x=pulseSpeed, y=depthInfluence, z=hueShift, w=mutationRate",
                          "  zoom_config: vec4<f32>,       // x=pulseSpeed, y=depthInfluence, z=hueShift, w=mutationRate\n  zoom_params: vec4<f32>,       // x=spreadSpeed, y=intensity, z=satThresh, w=tendrilScale")

with open("batch58a/chromatic-infection.wgsl", 'w') as f:
    f.write(content)
