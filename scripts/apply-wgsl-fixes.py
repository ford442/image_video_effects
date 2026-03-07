#!/usr/bin/env python3
"""
WGSL Auto-Fix Script

Applies automatic fixes to WGSL shaders based on audit reports.
Usage: python3 scripts/apply-wgsl-fixes.py [report_dir] [--dry-run] [--create-branch]
"""

import json
import os
import re
import sys
import shutil
import argparse
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Tuple


def load_json_reports(report_dir: str) -> Dict[str, List[dict]]:
    """Load all JSON report files from the report directory."""
    reports = {
        'syntax': [],
        'utf8': [],
        'portability': []
    }
    
    report_path = Path(report_dir)
    if not report_path.exists():
        print(f"❌ Report directory not found: {report_dir}")
        return reports
    
    for json_file in report_path.glob("*.json"):
        if json_file.name == "summary.json":
            continue
            
        try:
            with open(json_file, 'r', encoding='utf-8') as f:
                data = json.load(f)
                
            if json_file.name.startswith("syntax_"):
                reports['syntax'].append(data)
            elif json_file.name.startswith("utf8_"):
                reports['utf8'].append(data)
            elif json_file.name.startswith("portability_"):
                reports['portability'].append(data)
        except (json.JSONDecodeError, UnicodeDecodeError) as e:
            print(f"⚠️  Could not parse {json_file}: {e}")
    
    return reports


def fix_utf8_issues(file_path: str, report: dict, dry_run: bool = False) -> Tuple[bool, str]:
    """
    Apply UTF-8 encoding fixes to a shader file.
    Returns (success, description)
    """
    if report.get('status') != 'CORRUPTED':
        return False, "No UTF-8 issues to fix"
    
    try:
        # Read file with error handling
        with open(file_path, 'rb') as f:
            raw_content = f.read()
        
        # Remove BOM if present
        if raw_content.startswith(b'\xef\xbb\xbf'):
            raw_content = raw_content[3:]
        
        # Decode with replacement for invalid sequences
        content = raw_content.decode('utf-8', errors='replace')
        original_content = content
        
        # Apply fixes from report
        issues = report.get('issues', [])
        fixes_applied = []
        
        for issue in issues:
            issue_type = issue.get('type')
            original = issue.get('original', '')
            replacement = issue.get('replacement', '')
            
            if issue_type == 'mojibake' and original and replacement:
                if original in content:
                    content = content.replace(original, replacement)
                    fixes_applied.append(f"Replaced '{original}' with '{replacement}'")
            
            elif issue_type == 'null_bytes':
                content = content.replace('\x00', '')
                fixes_applied.append("Removed null bytes")
            
            elif issue_type == 'line_endings':
                # Normalize line endings to LF
                content = content.replace('\r\n', '\n').replace('\r', '\n')
                fixes_applied.append("Normalized line endings to LF")
        
        # Additional common mojibake fixes
        mojibake_map = {
            'â€œ': '"',
            'â€': '"',
            'â€™': "'",
            'â€¢': '*',
            'â€¦': '...',
            'Ã©': 'é',
            'Ã±': 'ñ',
            'Ã§': 'ç',
            'Ã¼': 'ü',
            'â€“': '-',
            'â€"': '—',
        }
        
        for bad, good in mojibake_map.items():
            if bad in content:
                content = content.replace(bad, good)
                fixes_applied.append(f"Fixed mojibake: {bad} -> {good}")
        
        # Remove replacement characters
        if '\ufffd' in content:
            content = content.replace('\ufffd', '')
            fixes_applied.append("Removed replacement characters")
        
        if content != original_content and not dry_run:
            # Backup original
            backup_path = file_path + '.bak'
            shutil.copy2(file_path, backup_path)
            
            # Write fixed content
            with open(file_path, 'w', encoding='utf-8', newline='\n') as f:
                f.write(content)
            
            return True, f"Applied {len(fixes_applied)} UTF-8 fixes: {', '.join(fixes_applied[:3])}"
        elif content != original_content:
            return True, f"[DRY-RUN] Would apply {len(fixes_applied)} UTF-8 fixes"
        
        return False, "No changes needed"
        
    except Exception as e:
        return False, f"Error fixing UTF-8: {str(e)}"


def fix_syntax_issues(file_path: str, report: dict, dry_run: bool = False) -> Tuple[bool, str]:
    """
    Apply syntax fixes to a shader file.
    Returns (success, description)
    """
    if report.get('status') != 'INVALID':
        return False, "No syntax errors to fix"
    
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        original_content = content
        fixes_applied = []
        errors = report.get('errors', [])
        
        for error in errors:
            line_num = error.get('line', 0)
            fix = error.get('fix', '')
            message = error.get('message', '')
            
            if fix and line_num > 0:
                # Simple line-by-line replacement (for simple fixes)
                lines = content.split('\n')
                if line_num <= len(lines):
                    # This is a simplified fix - in practice, more sophisticated
                    # parsing might be needed
                    if 'semicolon' in message.lower():
                        lines[line_num - 1] = lines[line_num - 1].rstrip() + ';'
                        fixes_applied.append(f"Added semicolon at line {line_num}")
                    elif fix not in content:
                        # For more complex fixes, the corrected_code is preferred
                        pass
        
        content = '\n'.join(lines)
        
        # If there's a corrected_code in the report, use that instead
        corrected = report.get('corrected_code')
        if corrected and corrected != original_content:
            content = corrected
            fixes_applied.append("Applied corrected code from report")
        
        if content != original_content and not dry_run:
            backup_path = file_path + '.bak'
            if not os.path.exists(backup_path):
                shutil.copy2(file_path, backup_path)
            
            with open(file_path, 'w', encoding='utf-8', newline='\n') as f:
                f.write(content)
            
            return True, f"Applied {len(fixes_applied)} syntax fixes"
        elif content != original_content:
            return True, f"[DRY-RUN] Would apply {len(fixes_applied)} syntax fixes"
        
        return False, "No syntax changes applied"
        
    except Exception as e:
        return False, f"Error fixing syntax: {str(e)}"


def generate_pr_description(fixes: List[Tuple[str, str, str]], summary_json: Optional[dict] = None) -> str:
    """Generate a PR description from the list of fixes."""
    lines = [
        "# WGSL Shader Audit Fixes",
        "",
        f"**Generated**: {datetime.now().isoformat()}",
        "",
        "## Summary",
        "",
    ]
    
    if summary_json:
        lines.extend([
            f"- Total shaders audited: {summary_json.get('total_shaders', 'N/A')}",
            f"- Syntax issues fixed: {summary_json.get('syntax', {}).get('invalid', 'N/A')}",
            f"- UTF-8 issues fixed: {summary_json.get('utf8', {}).get('corrupted', 'N/A')}",
            f"- Portability warnings: {summary_json.get('portability', {}).get('warnings', 'N/A')}",
            "",
        ])
    
    lines.extend([
        "## Files Modified",
        "",
    ])
    
    for file_path, fix_type, description in fixes:
        lines.append(f"### `{file_path}`")
        lines.append(f"- **Type**: {fix_type}")
        lines.append(f"- **Changes**: {description}")
        lines.append("")
    
    lines.extend([
        "## Changes Applied",
        "",
        "- Fixed UTF-8 encoding issues (BOM removal, mojibake correction)",
        "- Fixed syntax errors where automatic fixes were available",
        "- Normalized line endings to LF",
        "- Removed null bytes and replacement characters",
        "",
        "## Testing",
        "",
        "- [ ] Verify shaders compile in target application",
        "- [ ] Check visual output matches expected behavior",
        "- [ ] Test on multiple browsers (Chrome, Firefox, Safari)",
        "",
        "---",
        "*This PR was auto-generated by the WGSL Audit Swarm*",
    ])
    
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description='Apply WGSL shader fixes from audit reports')
    parser.add_argument('report_dir', nargs='?', default='reports',
                        help='Directory containing audit reports (default: reports)')
    parser.add_argument('--dry-run', action='store_true',
                        help='Show what would be fixed without making changes')
    parser.add_argument('--create-branch', action='store_true',
                        help='Create a git branch with the fixes')
    parser.add_argument('--fix-type', choices=['utf8', 'syntax', 'all'], default='all',
                        help='Type of fixes to apply (default: all)')
    
    args = parser.parse_args()
    
    # Find the most recent report directory if not specified directly
    report_dir = args.report_dir
    if not os.path.isdir(report_dir) or not any(f.endswith('.json') for f in os.listdir(report_dir)):
        # Look for timestamped report directories
        base_dir = report_dir
        if os.path.isdir(base_dir):
            subdirs = [d for d in os.listdir(base_dir) if os.path.isdir(os.path.join(base_dir, d))]
            subdirs.sort(reverse=True)
            if subdirs:
                report_dir = os.path.join(base_dir, subdirs[0])
                print(f"📁 Using most recent report: {report_dir}")
    
    # Load reports
    print(f"🔍 Loading reports from {report_dir}...")
    reports = load_json_reports(report_dir)
    
    total_syntax = len(reports['syntax'])
    total_utf8 = len(reports['utf8'])
    total_portability = len(reports['portability'])
    
    print(f"   Found: {total_syntax} syntax reports, {total_utf8} UTF-8 reports, {total_portability} portability reports")
    
    # Track fixes
    fixes_applied = []
    
    # Process UTF-8 fixes
    if args.fix_type in ('utf8', 'all'):
        print("\n🧹 Processing UTF-8 fixes...")
        for report in reports['utf8']:
            file_path = report.get('file')
            if not file_path or not os.path.exists(file_path):
                print(f"   ⚠️  File not found: {file_path}")
                continue
            
            success, description = fix_utf8_issues(file_path, report, args.dry_run)
            if success:
                fixes_applied.append((file_path, 'UTF-8', description))
                print(f"   ✅ {file_path}: {description}")
            else:
                print(f"   ℹ️  {file_path}: {description}")
    
    # Process syntax fixes
    if args.fix_type in ('syntax', 'all'):
        print("\n🔧 Processing syntax fixes...")
        for report in reports['syntax']:
            file_path = report.get('file')
            if not file_path or not os.path.exists(file_path):
                print(f"   ⚠️  File not found: {file_path}")
                continue
            
            success, description = fix_syntax_issues(file_path, report, args.dry_run)
            if success:
                fixes_applied.append((file_path, 'Syntax', description))
                print(f"   ✅ {file_path}: {description}")
            else:
                print(f"   ℹ️  {file_path}: {description}")
    
    # Summary
    print(f"\n📊 Summary")
    print(f"   Total fixes applied: {len(fixes_applied)}")
    
    if args.dry_run:
        print("\n⚠️  This was a dry run. No files were actually modified.")
        print("   Run without --dry-run to apply changes.")
    
    # Generate PR description if fixes were made
    if fixes_applied and not args.dry_run:
        # Load summary.json if available
        summary_json = None
        summary_path = os.path.join(report_dir, 'summary.json')
        if os.path.exists(summary_path):
            with open(summary_path, 'r') as f:
                summary_json = json.load(f)
        
        pr_description = generate_pr_description(fixes_applied, summary_json)
        pr_file = os.path.join(report_dir, 'PR_DESCRIPTION.md')
        with open(pr_file, 'w') as f:
            f.write(pr_description)
        print(f"\n📝 PR description saved to: {pr_file}")
        
        # Git branch creation
        if args.create_branch:
            branch_name = f"wgsl-audit-fixes-{datetime.now().strftime('%Y%m%d')}"
            print(f"\n🌿 Creating git branch: {branch_name}")
            os.system(f'git checkout -b {branch_name} 2>/dev/null || echo "Branch may already exist"')
            os.system('git add -A')
            os.system(f'git commit -m "fix(wgsl): automated audit fixes for {len(fixes_applied)} shaders"')
            print(f"\n✅ Changes committed to branch: {branch_name}")
            print(f"   To push: git push origin {branch_name}")
    
    return 0 if fixes_applied else 1


if __name__ == '__main__':
    sys.exit(main())
