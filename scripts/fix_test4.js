const fs = require('fs');
let code = fs.readFileSync('src/components/WebGPUCanvas.test.tsx', 'utf8');

// The test passed when using fireEvent.mouseDown, but it reported NaN.
// Let's change back to fireEvent.mouseDown! Oh wait, `NaN` came AFTER I changed to `pointerDown`. Oh wait, the previous failure before my `pointerDown` change was "Number of calls: 0", but after my change to `typeof` it failed with "NaN". Let's check `clientX`!
