const fs = require('fs');
let code = fs.readFileSync('src/components/WebGPUCanvas.tsx', 'utf8');
code = code.replace("onPointerDown={handleMouseDown}", "onPointerDown={handleMouseDown} onMouseDown={handleMouseDown}");
fs.writeFileSync('src/components/WebGPUCanvas.tsx', code);
