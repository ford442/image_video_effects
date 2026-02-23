#!/usr/bin/env python3
"""
Test script for Storage Manager Shader API
Usage: python test_shaders.py [--local]
"""

import argparse
import json
import os
import random
import requests
from pathlib import Path

DEFAULT_API = "https://ford442-storage-manager.hf.space"
LOCAL_API = "http://localhost:7860"

# Test shader WGSL code
TEST_SHADER_WGSL = '''// Test Generative Shader
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    let color = vec3<f32>(
        sin(uv.x * 3.14159 + time) * 0.5 + 0.5,
        sin(uv.y * 3.14159 + time * 1.5) * 0.5 + 0.5,
        sin((uv.x + uv.y) * 3.14159 + time * 0.5) * 0.5 + 0.5
    );
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
}
'''

def find_wgsl_files():
    """Find .wgsl files in public/shaders/"""
    shader_dir = Path("public/shaders")
    if shader_dir.exists():
        return list(shader_dir.glob("*.wgsl"))[:5]  # First 5 files
    return []

def create_test_shader():
    """Create a temporary test shader file"""
    test_dir = Path("test_shaders")
    test_dir.mkdir(exist_ok=True)
    test_file = test_dir / "test_effect.wgsl"
    test_file.write_text(TEST_SHADER_WGSL)
    return test_file

def upload_shader(api_base, file_path, name, description, tags, author="ford442"):
    """Upload a shader to the API"""
    url = f"{api_base}/api/shaders/upload"
    
    with open(file_path, 'rb') as f:
        files = {'file': f}
        data = {
            'name': name,
            'description': description,
            'tags': ','.join(tags),
            'author': author
        }
        
        response = requests.post(url, files=files, data=data)
        return response.json()

def rate_shader(api_base, shader_id, stars):
    """Rate a shader"""
    url = f"{api_base}/api/shaders/{shader_id}/rate"
    response = requests.post(url, data={'stars': stars})
    return response.json()

def list_shaders(api_base, category=None, sort_by='rating'):
    """List shaders from the API"""
    url = f"{api_base}/api/shaders"
    params = {'sort_by': sort_by}
    if category:
        params['category'] = category
    
    response = requests.get(url, params=params)
    return response.json()

def get_shader_code(api_base, shader_id):
    """Get shader code"""
    url = f"{api_base}/api/shaders/{shader_id}/code"
    response = requests.get(url)
    return response.json()

def health_check(api_base):
    """Check API health"""
    url = f"{api_base}/api/health"
    response = requests.get(url)
    return response.json()

def main():
    parser = argparse.ArgumentParser(description='Test Storage Manager Shader API')
    parser.add_argument('--local', action='store_true', help='Use local API instead of production')
    parser.add_argument('--skip-upload', action='store_true', help='Skip upload tests')
    args = parser.parse_args()
    
    api_base = LOCAL_API if args.local else DEFAULT_API
    print(f"=== Storage Manager Shader Test ===")
    print(f"API: {api_base}")
    print()
    
    # Health check
    print("=== Health Check ===")
    try:
        health = health_check(api_base)
        print(f"Status: {health.get('status', 'unknown')}")
        if 'storage' in health:
            for item_type, info in health['storage'].items():
                print(f"  {item_type}: {info.get('count', 0)} items")
    except Exception as e:
        print(f"❌ Health check failed: {e}")
        return
    print()
    
    if args.skip_upload:
        print("=== Skipping Upload Tests ===")
        uploaded_ids = []
    else:
        # Find or create test shaders
        wgsl_files = find_wgsl_files()
        if not wgsl_files:
            print("Creating test shader...")
            wgsl_files = [create_test_shader()]
        
        print(f"Found {len(wgsl_files)} shader(s) to upload")
        print()
        
        # Upload shaders
        print("=== Uploading Shaders ===")
        uploaded_ids = []
        
        for i, file_path in enumerate(wgsl_files, 1):
            name = file_path.stem.replace('-', ' ').replace('_', ' ').title()
            description = f"Auto-uploaded test shader from {file_path.name}"
            tags = ["generative", "test", "auto-upload"]
            
            print(f"Uploading: {name}...")
            try:
                result = upload_shader(api_base, file_path, name, description, tags)
                
                if result.get('success'):
                    shader_id = result['id']
                    uploaded_ids.append(shader_id)
                    print(f"  ✅ ID: {shader_id}")
                    
                    # Rate the shader
                    stars = random.choice([3, 4, 5])
                    print(f"  ⭐ Rating: {stars} stars")
                    rate_shader(api_base, shader_id, stars)
                else:
                    print(f"  ❌ Failed: {result}")
            except Exception as e:
                print(f"  ❌ Error: {e}")
            print()
    
    # List all shaders
    print("=== Listing All Shaders ===")
    try:
        shaders = list_shaders(api_base, sort_by='rating')
        print(f"Found {len(shaders)} shader(s)")
        for shader in shaders[:5]:  # Show first 5
            print(f"  - {shader.get('name', 'Unknown')} "
                  f"({shader.get('stars', 0):.1f}★, {shader.get('rating_count', 0)} ratings)")
    except Exception as e:
        print(f"❌ List failed: {e}")
    print()
    
    # List by category
    print("=== Listing Generative Shaders ===")
    try:
        shaders = list_shaders(api_base, category='generative', sort_by='rating')
        print(f"Found {len(shaders)} generative shader(s)")
    except Exception as e:
        print(f"❌ Category filter failed: {e}")
    print()
    
    # Test code fetch
    if uploaded_ids:
        test_id = uploaded_ids[0]
        print(f"=== Fetching Shader Code (ID: {test_id}) ===")
        try:
            code_data = get_shader_code(api_base, test_id)
            code = code_data.get('code', '')
            print(f"Name: {code_data.get('name', 'Unknown')}")
            print(f"Code length: {len(code)} chars")
            print(f"Preview: {code[:200]}...")
        except Exception as e:
            print(f"❌ Code fetch failed: {e}")
        print()
    
    print("=== Test Complete ===")
    print(f"View shaders at: {api_base}/api/shaders?sort_by=rating")

if __name__ == '__main__':
    main()
