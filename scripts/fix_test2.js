const fs = require('fs');
let code = fs.readFileSync('src/components/WebGPUCanvas.tsx', 'utf8');
console.log(code.includes("event.nativeEvent.clientX"));
