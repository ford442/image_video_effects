const fs = require('fs');
let code = fs.readFileSync('src/components/WebGPUCanvas.tsx', 'utf8');

// Print addRippleAtMouseEvent block
const lines = code.split('\n');
const start = lines.findIndex(l => l.includes('const addRippleAtMouseEvent'));
console.log(lines.slice(start, start + 10).join('\n'));

console.log('---');

const start2 = lines.findIndex(l => l.includes('const handleMouseDown'));
console.log(lines.slice(start2, start2 + 10).join('\n'));
