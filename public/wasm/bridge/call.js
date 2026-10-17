// GENERATED — do not edit. Source: src/wasm/ (concat_bridge.sh / emit-wasm-bridge.mjs)

const seams = /* @__PURE__ */ new WeakMap();
function seamOf(mod) {
  let s = seams.get(mod);
  if (!s) {
    s = { active: null, queued: 0, tail: Promise.resolve(), skipped: {} };
    seams.set(mod, s);
  }
  return s;
}
function logQueuedFailure(ident) {
  return (err) => console.error(`[WASM] queued ${ident} threw:`, err);
}
function enqueue(s, run) {
  s.queued += 1;
  const p = s.tail.then(() => {
    s.queued -= 1;
    return run();
  });
  s.tail = p.then(
    () => void 0,
    () => void 0
  );
  return p;
}
function hasExport(mod, ident) {
  return typeof mod[`_${ident}`] === "function";
}
function callAsync(mod, ident, returnType, argTypes, args) {
  const s = seamOf(mod);
  const start = () => {
    s.active = ident;
    let p;
    try {
      p = Promise.resolve(mod.ccall(ident, returnType, argTypes, args, { async: true }));
    } catch (err) {
      p = Promise.reject(err);
    }
    return p.finally(() => {
      if (s.active === ident) s.active = null;
    });
  };
  if (!s.active && s.queued === 0) {
    const p = start();
    s.tail = p.then(
      () => void 0,
      () => void 0
    );
    return p;
  }
  return enqueue(s, start);
}
function callSync(mod, ident, returnType, argTypes, args, whileSuspended, fallback) {
  const s = seamOf(mod);
  if (whileSuspended === "skip" && s.active) {
    s.skipped[ident] = (s.skipped[ident] ?? 0) + 1;
    return fallback;
  }
  if (whileSuspended === "queue" && (s.active || s.queued > 0)) {
    void enqueue(s, () => mod.ccall(ident, returnType, argTypes, args)).catch(logQueuedFailure(ident));
    return fallback;
  }
  return mod.ccall(ident, returnType, argTypes, args);
}
function isSuspended(mod) {
  return Boolean(mod && seams.get(mod)?.active);
}
function isBusy(mod) {
  const s = mod ? seams.get(mod) : void 0;
  return Boolean(s && (s.active || s.queued > 0));
}
function runWhenIdle(mod, fn) {
  const s = seamOf(mod);
  if (!s.active && s.queued === 0) {
    try {
      return Promise.resolve(fn());
    } catch (err) {
      return Promise.reject(err);
    }
  }
  return enqueue(s, fn);
}
function getSeamDiagnostics(mod) {
  const s = mod ? seams.get(mod) : void 0;
  return { active: s?.active ?? null, queued: s?.queued ?? 0, skipped: { ...s?.skipped ?? {} } };
}
export {
  callAsync,
  callSync,
  getSeamDiagnostics,
  hasExport,
  isBusy,
  isSuspended,
  runWhenIdle
};
