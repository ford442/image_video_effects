const fs = require('fs');
const path = require('path');

const shadersDir = './public/shaders';
const defsDir = './shader_definitions';

const categories = fs.readdirSync(defsDir).filter(d => fs.statSync(path.join(defsDir, d)).isDirectory());

const jsonShaders = new Map();
categories.forEach(function (cat) {
    const catPath = path.join(defsDir, cat);
    const files = fs.readdirSync(catPath).filter(function (f) { return f.endsWith('.json'); });
    files.forEach(function (f) {
        try {
            const content = fs.readFileSync(path.join(catPath, f), 'utf8');
            const def = JSON.parse(content);
            if (Array.isArray(def)) def = def[0];
            jsonShaders.set(def.id, { def: def, category: cat, jsonFile: f });
        } catch (e) { }
    });
});

const wgslFiles = fs.readdirSync(shadersDir).filter(function (f) { return f.endsWith('.wgsl'); });
const mismatches = [];
wgslFiles.forEach(function (f) {
    const code = fs.readFileSync(path.join(shadersDir, f), 'utf8');
    if (code.includes('u.zoom_config')) {
        const id = f.replace('.wgsl', '');
        const jsonDef = jsonShaders.get(id);
        if (!jsonDef || !jsonDef.def.features || !jsonDef.def.features.includes('mouse-driven')) {
            mismatches.push({
                wgsl: f,
                id: id,
                hasJson: !!jsonDef,
                features: jsonDef ? (jsonDef.def.features || []) : [],
                category: jsonDef ? jsonDef.category : 'unknown'
            });
        }
    }
});

console.log('AUDIT RESULTS: Shaders using u.zoom_config but missing \"mouse-driven\" feature tag');
console.log('================================================================================');
if (mismatches.length === 0) {
    console.log('✅ ALL shaders using u.zoom_config have \"mouse-driven\" tag!');
} else {
    console.log('❌ MISMATCHES FOUND (' + mismatches.length + '):');
    mismatches.forEach(function (m) {
        console.log('  WGSL: ' + m.wgsl + ' (id: ' + m.id + ')');
        console.log('     JSON: ' + (m.hasJson ? 'exists' : 'MISSING') + ', features: [' + m.features.join(', ') + ']');
        console.log('     Category: ' + m.category);
        console.log('');
    });
}

const args = process.argv.slice(2);
const updateTags = args.includes('--update-tags');

if (updateTags && mismatches.length > 0) {
    console.log(`\n📝 Updating ${mismatches.length} JSON files with "mouse-driven" tag...\n`);
    let updatedCount = 0;
    mismatches.forEach(m => {
        if (m.hasJson) {
            const fullPath = path.join(defsDir, m.category, m.jsonFile);
            try {
                const content = fs.readFileSync(fullPath, 'utf8');
                const def = JSON.parse(content);
                if (Array.isArray(def)) def = def[0];
                if (!def.features) def.features = [];
                if (!def.features.includes('mouse-driven')) {
                    def.features.push('mouse-driven');
                    fs.writeFileSync(fullPath, JSON.stringify(def, null, 2));
                    updatedCount++;
                    console.log(`  ✅ Updated ${m.id} (${m.jsonFile})`);
                }
            } catch (e) {
                console.log(`  ❌ Failed to update ${m.id}: ${e.message}`);
            }
        }
    });
    console.log(`\n✨ Completed: ${updatedCount}/${mismatches.length} files updated.\n`);
}

console.log('');
console.log('Total JSON shaders: ' + jsonShaders.size);
