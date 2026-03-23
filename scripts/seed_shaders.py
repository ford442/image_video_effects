#!/usr/bin/env python3
"""
Seed shader files into the storage manager.
Reads .wgsl files from public/shaders and uploads them with metadata.
"""

import os
import json
import aiohttp
import asyncio
from pathlib import Path
from datetime import datetime

# Configuration
SHADER_DIR = Path(__file__).parent.parent / "public" / "shaders"
STORAGE_API = "https://ford442-storage-manager.hf.space"
UPLOAD_ENDPOINT = f"{STORAGE_API}/api/shaders/upload"

# Category mapping based on shader filename patterns
CATEGORY_KEYWORDS = {
    "interactive": ["interactive", "touch", "mouse", "cursor"],
    "generative": ["generative", "procedural", "noise", "flow"],
    "distortion": ["distort", "warp", "twist", "bend", "glitch"],
    "image": ["filter", "effect", "color", "tone", "lens"],
    "artistic": ["paint", "brush", "sketch", "art", "style"],
}

def infer_category(filename: str) -> str:
    """Infer shader category from filename."""
    name_lower = filename.lower()
    for category, keywords in CATEGORY_KEYWORDS.items():
        if any(kw in name_lower for kw in keywords):
            return category
    return "artistic"  # default

def get_shader_metadata(shader_file: Path) -> dict:
    """Create metadata for a shader file."""
    name = shader_file.stem.replace("-", " ").title()
    category = infer_category(shader_file.name)

    return {
        "name": name,
        "description": f"Shader: {name}",
        "tags": [category],
        "author": "ford442",
        "category": category,
    }

async def upload_shader(session: aiohttp.ClientSession, shader_file: Path) -> bool:
    """Upload a single shader file."""
    try:
        metadata = get_shader_metadata(shader_file)

        with open(shader_file, "rb") as f:
            data = aiohttp.FormData()
            data.add_field("file", f, filename=shader_file.name)
            data.add_field("name", metadata["name"])
            data.add_field("description", metadata["description"])
            data.add_field("tags", ",".join(metadata["tags"]))
            data.add_field("author", metadata["author"])

            async with session.post(UPLOAD_ENDPOINT, data=data) as resp:
                if resp.status == 200:
                    print(f"✓ {shader_file.name}")
                    return True
                else:
                    print(f"✗ {shader_file.name}: {resp.status}")
                    return False
    except Exception as e:
        print(f"✗ {shader_file.name}: {e}")
        return False

async def seed_shaders():
    """Seed all shaders from the public directory."""
    if not SHADER_DIR.exists():
        print(f"Error: Shader directory not found: {SHADER_DIR}")
        return

    shader_files = sorted([f for f in SHADER_DIR.glob("*.wgsl") if not f.name.startswith("_")])

    if not shader_files:
        print("No shader files found!")
        return

    print(f"Found {len(shader_files)} shaders. Starting upload...")

    async with aiohttp.ClientSession() as session:
        tasks = [upload_shader(session, f) for f in shader_files[:100]]  # Limit to 100 initially
        results = await asyncio.gather(*tasks)

        success_count = sum(results)
        print(f"\nUploaded {success_count}/{len(shader_files)} shaders")

if __name__ == "__main__":
    asyncio.run(seed_shaders())
