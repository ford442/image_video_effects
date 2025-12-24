const fs = require('fs');
const path = require('path');

const DEFINITIONS_DIR = path.join(__dirname, '../shader_definitions');
const OUTPUT_DIR = path.join(__dirname, '../public/shader-lists');

// Ensure output directory exists
if (!fs.existsSync(OUTPUT_DIR)) {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}

// Get all category folders (interactive-mouse, artistic, etc.)
if (fs.existsSync(DEFINITIONS_DIR)) {
    const categories = fs.readdirSync(DEFINITIONS_DIR).filter(file => {
        return fs.statSync(path.join(DEFINITIONS_DIR, file)).isDirectory();
    });

    categories.forEach(category => {
        const categoryPath = path.join(DEFINITIONS_DIR, category);
        const files = fs.readdirSync(categoryPath).filter(f => f.endsWith('.json'));

        const shaderList = [];

        files.forEach(file => {
            const content = fs.readFileSync(path.join(categoryPath, file), 'utf-8');
            try {
                const shaderDef = JSON.parse(content);
                shaderList.push(shaderDef);
            } catch (e) {
                console.error(`Error parsing ${category}/${file}:`, e);
            }
        });

        const outputPath = path.join(OUTPUT_DIR, `${category}.json`);
        fs.writeFileSync(outputPath, JSON.stringify(shaderList, null, 2));
        console.log(`Generated ${category}.json with ${shaderList.length} shaders.`);
    });
} else {
    console.log("No shader_definitions directory found.");
}
