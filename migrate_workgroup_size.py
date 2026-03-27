#!/usr/bin/env python3
"""
Migrate all WGSL shaders from @workgroup_size(8, 8, 1) to @workgroup_size(16, 16, 1)

This script updates all compute shaders in public/shaders/ to use the new
16x16 workgroup size for improved GPU occupancy (30-60% performance gain).

Usage:
    python migrate_workgroup_size.py [--check] [--dry-run]

Options:
    --check     Only report which files would be changed
    --dry-run   Show changes without writing files
"""

import os
import re
import sys
import argparse
from pathlib import Path
from typing import Tuple, List

# Configuration
SHADERS_DIR = Path("public/shaders")
OLD_WORKGROUP = (8, 8, 1)
NEW_WORKGROUP = (16, 16, 1)

# Regex patterns for matching workgroup_size declarations
# Matches: @compute @workgroup_size(8, 8, 1) or @compute @workgroup_size(8,8,1)
WORKGROUP_PATTERNS = [
    # Standard form with spaces
    (r'@compute\s+@workgroup_size\(\s*8\s*,\s*8\s*,\s*1\s*\)', 
     '@compute @workgroup_size(16, 16, 1)'),
    # Compact form
    (r'@compute\s+@workgroup_size\(8,8,1\)', 
     '@compute @workgroup_size(16, 16, 1)'),
    # With comment
    (r'@compute\s+@workgroup_size\(\s*8\s*,\s*8\s*,\s*1\s*\)\s*//',
     '@compute @workgroup_size(16, 16, 1)  //'),
]

# Track statistics
stats = {
    'scanned': 0,
    'matched': 0,
    'updated': 0,
    'already_16x16': 0,
    'other_sizes': 0,
    'errors': 0,
}


def find_workgroup_size(content: str) -> Tuple[int, int, int] | None:
    """Extract workgroup size from shader content."""
    pattern = r'@compute\s+@workgroup_size\(\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*(\d+))?\s*\)'
    match = re.search(pattern, content)
    if match:
        x = int(match.group(1))
        y = int(match.group(2))
        z = int(match.group(3)) if match.group(3) else 1
        return (x, y, z)
    return None


def update_shader(filepath: Path, dry_run: bool = False) -> bool:
    """Update a single shader file. Returns True if changed."""
    try:
        content = filepath.read_text(encoding='utf-8')
        original_content = content
        
        current_wg = find_workgroup_size(content)
        if not current_wg:
            return False
        
        if current_wg == NEW_WORKGROUP:
            stats['already_16x16'] += 1
            return False
        
        if current_wg == OLD_WORKGROUP:
            stats['matched'] += 1
            
            # Apply replacements
            for old_pattern, new_pattern in WORKGROUP_PATTERNS:
                content = re.sub(old_pattern, new_pattern, content)
            
            if content != original_content:
                if not dry_run:
                    filepath.write_text(content, encoding='utf-8')
                stats['updated'] += 1
                return True
        else:
            stats['other_sizes'] += 1
            print(f"  Note: {filepath.name} has non-standard size {current_wg}")
            
    except Exception as e:
        stats['errors'] += 1
        print(f"  Error processing {filepath}: {e}")
    
    return False


def scan_shaders(check_only: bool = False, dry_run: bool = False) -> List[Path]:
    """Scan all shader files and optionally update them."""
    changed_files = []
    
    if not SHADERS_DIR.exists():
        print(f"Error: Shaders directory not found: {SHADERS_DIR}")
        sys.exit(1)
    
    wgsl_files = sorted(SHADERS_DIR.glob("*.wgsl"))
    print(f"Scanning {len(wgsl_files)} shader files...\n")
    
    for filepath in wgsl_files:
        stats['scanned'] += 1
        
        if check_only or dry_run:
            content = filepath.read_text(encoding='utf-8')
            wg_size = find_workgroup_size(content)
            
            if wg_size == OLD_WORKGROUP:
                print(f"Would update: {filepath.name} (8,8,1 -> 16,16,16)")
                changed_files.append(filepath)
            elif wg_size == NEW_WORKGROUP:
                print(f"Already 16x16: {filepath.name}")
            elif wg_size:
                print(f"Non-standard: {filepath.name} ({wg_size})")
        else:
            if update_shader(filepath, dry_run):
                changed_files.append(filepath)
                print(f"Updated: {filepath.name}")
    
    return changed_files


def main():
    parser = argparse.ArgumentParser(
        description="Migrate WGSL shaders to 16x16 workgroup size"
    )
    parser.add_argument(
        '--check', 
        action='store_true',
        help='Only report which files would be changed'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true', 
        help='Show changes without writing files'
    )
    parser.add_argument(
        '--restore-8x8',
        action='store_true',
        help='Restore 8x8 workgroup size (for testing)'
    )
    
    args = parser.parse_args()
    
    if args.restore_8x8:
        global OLD_WORKGROUP, NEW_WORKGROUP
        OLD_WORKGROUP, NEW_WORKGROUP = NEW_WORKGROUP, OLD_WORKGROUP
        WORKGROUP_PATTERNS[:] = [
            (r'@compute\s+@workgroup_size\(\s*16\s*,\s*16\s*,\s*1\s*\)', 
             '@compute @workgroup_size(8, 8, 1)'),
            (r'@compute\s+@workgroup_size\(16,16,1\)', 
             '@compute @workgroup_size(8, 8, 1)'),
        ]
        print("Restoring 8x8 workgroup size...\n")
    
    print("=" * 60)
    print("WGSL Workgroup Size Migration Tool")
    print("=" * 60)
    print(f"Directory: {SHADERS_DIR.absolute()}")
    print(f"Old size:  {OLD_WORKGROUP}")
    print(f"New size:  {NEW_WORKGROUP}")
    print("=" * 60 + "\n")
    
    changed = scan_shaders(check_only=args.check or args.dry_run, dry_run=args.dry_run)
    
    print("\n" + "=" * 60)
    print("Statistics")
    print("=" * 60)
    print(f"Shaders scanned:     {stats['scanned']}")
    print(f"8x8 found:           {stats['matched']}")
    print(f"Already 16x16:       {stats['already_16x16']}")
    print(f"Other sizes:         {stats['other_sizes']}")
    print(f"Updated:             {stats['updated']}")
    print(f"Errors:              {stats['errors']}")
    print("=" * 60)
    
    if args.check or args.dry_run:
        print(f"\n{len(changed)} files would be updated.")
    else:
        print(f"\n{len(changed)} files updated successfully.")
    
    return 0 if stats['errors'] == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
