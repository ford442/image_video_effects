import glob
import re

for filepath in glob.glob("batch58a/*.wgsl"):
    with open(filepath, 'r') as f:
        content = f.read()

    # Apply ACES tonemap to the rgb output
    
    # chromatic-phase-inversion
    content = re.sub(r'textureStore\(writeTexture, (.*?), vec4<f32>\((.*?), (.*?), (.*?), (.*?)\)\);',
                     r'textureStore(writeTexture, \1, vec4<f32>(aces_tonemap(vec3<f32>(\2, \3, \4)), \5));', content)

    # chromatic-folds, chromatic-infection
    content = re.sub(r'textureStore\(writeTexture, (.*?), vec4<f32>\(([^,]+?), 1\.0\)\);',
                     r'textureStore(writeTexture, \1, vec4<f32>(aces_tonemap(\2), 1.0));', content)

    # chromatic-ghost-tunnel
    content = re.sub(r'textureStore\(writeTexture, (.*?), vec4<f32>\(outRGB \* a, a\)\);',
                     r'textureStore(writeTexture, \1, vec4<f32>(aces_tonemap(outRGB * a), a));', content)
                     
    # chroma-vortex, chromatic-manifold, chromatic-swirl
    content = re.sub(r'textureStore\(writeTexture, (.*?), vec4<f32>\(([^,]+?), finalAlpha\)\);',
                     r'textureStore(writeTexture, \1, vec4<f32>(aces_tonemap(\2), finalAlpha));', content)

    # elastic-chromatic
    content = re.sub(r'textureStore\(writeTexture, (.*?), vec4<f32>\(srgbOut \* effectAlpha, effectAlpha\)\);',
                     r'textureStore(writeTexture, \1, vec4<f32>(aces_tonemap(srgbOut * effectAlpha), effectAlpha));', content)

    # chroma-kinetic: finalRGBA
    if 'finalRGBA' in content and 'textureStore(writeTexture, vec2<i32>(global_id.xy), finalRGBA)' in content:
        content = content.replace('textureStore(writeTexture, vec2<i32>(global_id.xy), finalRGBA);',
                                  'textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(aces_tonemap(finalRGBA.rgb), finalRGBA.a));')

    # chroma-lens: color
    if 'textureStore(writeTexture, vec2<i32>(global_id.xy), color)' in content:
        content = content.replace('textureStore(writeTexture, vec2<i32>(global_id.xy), color);',
                                  'textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(aces_tonemap(color.rgb), color.a));')

    with open(filepath, 'w') as f:
        f.write(content)
