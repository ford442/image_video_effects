// GENERATED — do not edit. Source: src/wasm/ (concat_bridge.sh / emit-wasm-bridge.mjs)

const SUSPENDING_EXPORTS = [
  "initWasmRenderer",
  "loadShader",
  "reloadShader",
  "resizeCanvas",
  "setColorFormat"
];
let tail = Promise.resolve();
let pending = 0;
let idleWaiters = [];
function callSuspending(module, ident, returnType, argTypes, args) {
  pending += 1;
  const result = tail.then(() => module.ccall(ident, returnType, argTypes, args, { async: true }));
  tail = result.catch(() => void 0);
  return result.finally(() => {
    pending -= 1;
    if (pending === 0) {
      const waiters = idleWaiters;
      idleWaiters = [];
      waiters.forEach((w) => w());
    }
  });
}
function isSuspended() {
  return pending > 0;
}
function whenIdle(fn) {
  if (pending === 0) fn();
  else idleWaiters.push(fn);
}
function resetSuspendingQueueForTests() {
  tail = Promise.resolve();
  pending = 0;
  idleWaiters = [];
}
export {
  SUSPENDING_EXPORTS,
  callSuspending,
  isSuspended,
  resetSuspendingQueueForTests,
  whenIdle
};
