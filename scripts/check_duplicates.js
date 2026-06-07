#!/usr/bin/env node
/**
 * Check for duplicate shader IDs across all shader definitions
 */

const fs = require('fs');
const path = require('path');

const defsDir = './shader_definitions';
const categories = fs.readdirSync(defsDir).filter(d => {
    return fs.statSync(path.join(defsDir, d)).isDirectory();
});

const ids = new Map();
const duplicates = [];
let total = 0;

categories.forEach(cat => {
    const catPath = path.join(defsDir, cat);
    const files = fs.readdirSync(catPath).filter(f => f.endsWith('.json'));
    
    files.forEach(f => {
        try {
            const content = fs.readFileSync(path.join(catPath, f), 'utf8');
            const def = JSON.parse(content);
            const defs = Array.isArray(def) ? def : [def];
            
            defs.forEach(d => {
                total++;
                if (ids.has(d.id)) {
                    duplicates.push({
                        id: d.id,
                        first: ids.get(d.id),
                        duplicate: { category: cat, file: f }
                    });
                } else {
                    ids.set(d.id, { category: cat, file: f });
                }
            });
        } catch (e) {
            console.error(`Error parsing ${cat}/${f}: ${e.message}`);
        }
    });
});

console.log('DUPLICATE CHECK RESULTS');
console.log('=======================');
console.log(`Total shader definitions: ${total}`);
console.log(`Unique IDs: ${ids.size}`);

if (duplicates.length === 0) {
    console.log('✅ No duplicate IDs found!');
    process.exit(0);
} else {
    console.log(`❌ Found ${duplicates.length} duplicate ID(s):`);
    duplicates.forEach(d => {
        console.log(`  "${d.id}" appears in:`);
        console.log(`    - ${d.first.category}/${d.first.file}`);
        console.log(`    - ${d.duplicate.category}/${d.duplicate.file}`);
    });
    process.exit(1);
}
