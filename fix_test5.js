const fs = require('fs');
let code = fs.readFileSync('src/components/WebGPUCanvas.test.tsx', 'utf8');
code = code.replace("fireEvent.pointerDown(canvas, { clientX: 100, clientY: 50 });", "fireEvent.mouseDown(canvas, { clientX: 100, clientY: 50 });");
fs.writeFileSync('src/components/WebGPUCanvas.test.tsx', code);
