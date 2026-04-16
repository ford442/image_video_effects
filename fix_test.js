const fs = require('fs');
let code = fs.readFileSync('src/components/WebGPUCanvas.test.tsx', 'utf8');

// The issue might be that rect.width or rect.height is 0.
// Let's check how the test mocks getBoundingClientRect.
console.log(code);
