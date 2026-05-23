const fs = require('fs');
const path = require('path');

const DEFINITIONS_DIR = path.join(__dirname, '../shader_definitions');

console.log("Removing 'category' field from all shader definitions...\n");

let totalShaders = 0;
let cleanedShaders = 0;
const errors = [];

if (!fs.existsSync(DEFINITIONS_DIR)) {
    console.error("shader_definitions directory not found.");
    process.exit(1);
}

// Walk through all category folders
const categories = fs.readdirSync(DEFINITIONS_DIR).filter(file => {
    return fs.statSync(path.join(DEFINITIONS_DIR, file)).isDirectory();
});

categories.forEach(dir => {
    const dirPath = path.join(DEFINITIONS_DIR, dir);
    const files = fs.readdirSync(dirPath).filter(f => f.endsWith('.json'));

    files.forEach(file => {
        const filePath = path.join(dirPath, file);
        try {
            const content = fs.readFileSync(filePath, 'utf-8');
            let shaderDef = JSON.parse(content);

            // Handle array-wrapped definitions
            if (Array.isArray(shaderDef)) {
                // Process each item in the array
                shaderDef = shaderDef.map(shader => {
                    totalShaders++;
                    if (shader.category) {
                        delete shader.category;
                        cleanedShaders++;
                    }
                    return shader;
                });
            } else {
                // Single object
                totalShaders++;
                if (shaderDef.category) {
                    delete shaderDef.category;
                    cleanedShaders++;
                }
            }

            // Write back with consistent formatting
            fs.writeFileSync(filePath, JSON.stringify(shaderDef, null, 2) + '\n');

        } catch (e) {
            errors.push({ file: `${dir}/${file}`, error: e.message });
        }
    });
});

// Summary
console.log(`✓ Processed ${totalShaders} shader definitions`);
console.log(`✓ Removed 'category' field from ${cleanedShaders} shaders`);

if (errors.length > 0) {
    console.log(`\n⚠ Errors encountered (${errors.length}):`);
    errors.forEach(e => console.log(`  - ${e.file}: ${e.error}`));
    process.exit(1);
} else {
    console.log("\n✓ All shader definitions cleaned successfully!");
    process.exit(0);
}
