const fs = require('fs');
const path = require('path');

const DEFINITIONS_DIR = path.join(__dirname, '../shader_definitions');
const OUTPUT_DIR = path.join(__dirname, '../public/shader-lists');
const PUBLIC_DIR = path.join(__dirname, '../public');

// Ensure output directory exists
if (!fs.existsSync(OUTPUT_DIR)) {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}

// Global registry to track IDs and prevent duplicates
const seenIds = new Map(); // Map<id, category/filename>
const missingFiles = [];
const skippedDuplicates = [];

console.log("Generating shader lists...");

if (fs.existsSync(DEFINITIONS_DIR)) {
    const categories = fs.readdirSync(DEFINITIONS_DIR).filter(file => {
        return fs.statSync(path.join(DEFINITIONS_DIR, file)).isDirectory();
    });

    categories.forEach(category => {
        const categoryPath = path.join(DEFINITIONS_DIR, category);
        const files = fs.readdirSync(categoryPath).filter(f => f.endsWith('.json'));

        const validShaders = [];

        files.forEach(file => {
            const filePath = path.join(categoryPath, file);
            const content = fs.readFileSync(filePath, 'utf-8');
            try {
                let shaderDef = JSON.parse(content);

                // Handle array-wrapped definitions (normalize to single object)
                if (Array.isArray(shaderDef)) {
                    if (shaderDef.length > 0) {
                        shaderDef = shaderDef[0];
                    } else {
                        console.warn(`Empty array in ${category}/${file}`);
                        return;
                    }
                }

                const { id, url } = shaderDef;

                // 1. Check for Duplicate IDs
                if (seenIds.has(id)) {
                    console.warn(`WARNING: Duplicate ID '${id}' in ${category}/${file}. (Already defined in ${seenIds.get(id)}) - SKIPPING`);
                    skippedDuplicates.push({ id, file: `${category}/${file}`, original: seenIds.get(id) });
                    return;
                }

                // 2. Check for Missing WGSL File
                // url is typically "shaders/filename.wgsl" relative to public/
                const wgslPath = path.join(PUBLIC_DIR, url);
                if (!fs.existsSync(wgslPath)) {
                    console.warn(`WARNING: Missing WGSL file for '${id}' in ${category}/${file}. Expected at: ${wgslPath} - SKIPPING`);
                    missingFiles.push({ id, file: `${category}/${file}`, path: url });
                    return;
                }

                // Passed checks
                seenIds.set(id, `${category}/${file}`);
                validShaders.push(shaderDef);

            } catch (e) {
                console.error(`Error parsing ${category}/${file}:`, e);
            }
        });

        // Write the category JSON
        const outputPath = path.join(OUTPUT_DIR, `${category}.json`);
        fs.writeFileSync(outputPath, JSON.stringify(validShaders, null, 2));
        console.log(`Generated ${category}.json with ${validShaders.length} shaders.`);
    });

    // Summary Report
    console.log("\n--- Generation Summary ---");
    if (skippedDuplicates.length > 0) {
        console.log(`\nSKIPPED DUPLICATES (${skippedDuplicates.length}):`);
        skippedDuplicates.forEach(d => console.log(`  - ${d.id} (in ${d.file}, duplicate of ${d.original})`));
    }
    if (missingFiles.length > 0) {
        console.log(`\nSKIPPED MISSING FILES (${missingFiles.length}):`);
        missingFiles.forEach(f => console.log(`  - ${f.id} (wgsl: ${f.path})`));
    }
    console.log("\nDone.");

} else {
    console.log("No shader_definitions directory found.");
}
