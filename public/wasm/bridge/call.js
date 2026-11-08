// GENERATED — do not edit. Source: src/wasm/ (concat_bridge.sh / emit-wasm-bridge.mjs)

const seams = /* @__PURE__ */ new WeakMap();
function seamOf(mod) {
  let s = seams.get(mod);
  if (!s) {
    s = { active: null, queue: [], draining: false, skipped: {} };
    seams.set(mod, s);
  }
  return s;
}
function blocked(s) {
  return s.active !== null || s.queue.length > 0 && !s.draining;
}
function enqueue(s, run) {
  return new Promise((resolve, reject) => {
    s.queue.push({ run, resolve, reject });
  });
}
function drain(s) {
  while (s.active === null) {
    const task = s.queue.shift();
    if (!task) return;
    s.draining = true;
    try {
      task.resolve(task.run());
    } catch (err) {
      task.reject(err);
    } finally {
      s.draining = false;
    }
  }
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
      s.active = null;
      drain(s);
    });
  };
  return blocked(s) ? enqueue(s, start) : start();
}
function withPolicy(s, ident, whileSuspended, fallback, run) {
  if (whileSuspended === "skip" && s.active) {
    s.skipped[ident] = (s.skipped[ident] ?? 0) + 1;
    return fallback;
  }
  if (whileSuspended === "queue" && blocked(s)) {
    enqueue(s, run).catch((err) => console.error(`[WASM] queued ${ident} threw:`, err));
    return fallback;
  }
  return run();
}
function callSync(mod, ident, returnType, argTypes, args, whileSuspended, fallback) {
  return withPolicy(
    seamOf(mod),
    ident,
    whileSuspended,
    fallback,
    () => mod.ccall(ident, returnType, argTypes, args)
  );
}
function callDirect(mod, ident, returnType, args, whileSuspended, fallback) {
  const fn = mod[`_${ident}`];
  return withPolicy(seamOf(mod), ident, whileSuspended, fallback, () => {
    const r = fn(...args);
    if (returnType !== "string") return r;
    if (typeof mod.UTF8ToString !== "function") throw new Error(`[WASM] ${ident}: module lacks UTF8ToString`);
    return mod.UTF8ToString(Number(r));
  });
}
function isSuspended(mod) {
  return Boolean(mod && seams.get(mod)?.active);
}
function isBusy(mod) {
  const s = mod ? seams.get(mod) : void 0;
  return Boolean(s && blocked(s));
}
function runWhenIdle(mod, fn) {
  const s = seamOf(mod);
  if (!blocked(s)) {
    try {
      return Promise.resolve(fn());
    } catch (err) {
      return Promise.reject(err);
    }
  }
  return enqueue(s, fn);
}
function abandonSeam(mod) {
  const s = seams.get(mod);
  if (!s) return;
  const dropped = s.queue.splice(0);
  s.active = null;
  for (const task of dropped) task.reject(new Error("[WASM] module abandoned before this call ran"));
}
function getSeamDiagnostics(mod) {
  const s = mod ? seams.get(mod) : void 0;
  return { active: s?.active ?? null, queued: s?.queue.length ?? 0, skipped: { ...s?.skipped ?? {} } };
}
export {
  abandonSeam,
  callAsync,
  callDirect,
  callSync,
  getSeamDiagnostics,
  hasExport,
  isBusy,
  isSuspended,
  runWhenIdle
};
