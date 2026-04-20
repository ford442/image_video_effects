import json
import os
from pathlib import Path
from collections import defaultdict

def extract_params():
    definitions_dir = Path("/root/image_video_effects/shader_definitions")
    
    # Stats
    total_files = 0
    shaders_with_params = 0
    categories = set()
    
    # Output structure
    output = {}
    
    # Find all JSON files
    json_files = sorted(definitions_dir.rglob("*.json"))
    total_files = len(json_files)
    
    for json_file in json_files:
        try:
            with open(json_file, 'r') as f:
                data = json.load(f)
            
            # Handle array format (like post-processing.json)
            if isinstance(data, list):
                for item in data:
                    shader_id = item.get('id')
                    category = item.get('category')
                    params = item.get('params', [])
                    uniforms = item.get('uniforms', {})
                    
                    if not shader_id:
                        continue
                    
                    categories.add(category)
                    
                    # Convert uniforms to params format if no params exist
                    if not params and uniforms:
                        for i, (key, val) in enumerate(uniforms.items()):
                            param = {
                                "id": key,
                                "name": val.get('label', key),
                                "default": val.get('default', 0.5),
                                "min": val.get('min', 0),
                                "max": val.get('max', 1),
                                "mapping": f"zoom_params.{chr(ord('x') + i)}" if i < 4 else None
                            }
                            if 'step' in val:
                                param['step'] = val['step']
                            params.append(param)
                    
                    entry = {
                        "category": category,
                        "params": params if params else []
                    }
                    
                    if params:
                        shaders_with_params += 1
                        
                    output[shader_id] = entry
            
            # Handle object format (standard)
            elif isinstance(data, dict):
                shader_id = data.get('id')
                category = data.get('category')
                params = data.get('params', [])
                
                if not shader_id:
                    continue
                    
                categories.add(category)
                
                # Build entry
                entry = {
                    "category": category,
                    "params": params if params else []
                }
                
                if params:
                    shaders_with_params += 1
                    
                output[shader_id] = entry
            
        except Exception as e:
            print(f"Error processing {json_file}: {e}")
            continue
    
    # Save consolidated output
    with open("/root/image_video_effects/reports/shader_params_extracted.json", 'w') as f:
        json.dump(output, f, indent=2)
    
    # Generate report
    report = f"""# Shader Parameters Extraction Report

## Summary Statistics

| Metric | Value |
|--------|-------|
| Total JSON files found | {total_files} |
| Total shaders extracted | {len(output)} |
| Shaders with params | {shaders_with_params} |
| Categories covered | {len(categories)} |

## Categories

"""
    
    # Count shaders per category
    category_counts = defaultdict(int)
    category_with_params = defaultdict(int)
    
    for shader_id, data in output.items():
        cat = data['category']
        category_counts[cat] += 1
        if data['params']:
            category_with_params[cat] += 1
    
    for cat in sorted(categories):
        report += f"- **{cat}**: {category_counts[cat]} shaders ({category_with_params[cat]} with params)\\n"
    
    # Sample of extracted data
    report += """
## Sample Extracted Data

```json
{
"""
    
    # Show first 3 shaders with params as examples
    examples = [(k, v) for k, v in output.items() if v['params']][:3]
    for i, (shader_id, data) in enumerate(examples):
        report += f'''  "{shader_id}": {{
    "category": "{data['category']}",
    "params": {json.dumps(data['params'], indent=4)}
  }}'''
        if i < len(examples) - 1:
            report += ",\n"
    
    report += """
}
```

## Parameter Schema

Each parameter object contains:
- `id`: Parameter identifier (string)
- `name`: Display name (string)
- `default`: Default value (number)
- `min`: Minimum value (number)
- `max`: Maximum value (number)
- `step`: Step increment (number, optional)
- `mapping`: WGSL uniform mapping (string, optional)
- `description`: Parameter description (string, optional)

## Output File

Extracted data saved to: `shader_params_extracted.json`
"""
    
    with open("/root/image_video_effects/notes/extraction_report.md", 'w') as f:
        f.write(report)
    
    print(f"Extraction complete!")
    print(f"Total JSON files: {total_files}")
    print(f"Total shaders: {len(output)}")
    print(f"Shaders with params: {shaders_with_params}")
    print(f"Categories: {len(categories)}")

if __name__ == "__main__":
    extract_params()
