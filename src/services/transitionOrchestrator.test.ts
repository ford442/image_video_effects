import { TransitionOrchestrator, TransitionSchemaSlot } from './transitionOrchestrator';

const schemaA: TransitionSchemaSlot[] = [{ params: { a: { min: 0, max: 1, step: 0.1 } } }];
const schemaB: TransitionSchemaSlot[] = [{ params: { b: { min: 0, max: 1, step: 0.1 } } }];

describe('TransitionOrchestrator', () => {
  test('tab-throttle jump advances by elapsed dt without overshoot', async () => {
    const orchestrator = new TransitionOrchestrator({ source: 'timer', intervalMs: 5000, durationMs: 5000 });
    orchestrator.start({
      params: [{ a: 0 }],
      schema: schemaA,
      shaderSignature: 'a',
      now: 0,
    });

    await orchestrator.trigger({ params: [{ a: 1 }], schema: schemaA, shaderSignature: 'a' });
    const result = await orchestrator.update(3000);

    expect(result).not.toBeNull();
    expect(result!.progress).toBeCloseTo(0.6, 5);
    expect(result!.params[0].a).toBeLessThanOrEqual(1);
  });

  test('schema change mid-transition rebases safely with no NaN', async () => {
    const orchestrator = new TransitionOrchestrator({ source: 'timer', intervalMs: 1000, durationMs: 1000 });
    orchestrator.start({ params: [{ a: 0 }], schema: schemaA, shaderSignature: 'stack-a', now: 0 });

    await orchestrator.trigger({ params: [{ a: 1 }], schema: schemaA, shaderSignature: 'stack-a' });
    const at40 = await orchestrator.update(400);
    expect(at40).not.toBeNull();

    const rebasedStart = at40!.params[0].a;
    orchestrator.setBaseline({
      params: [{ b: rebasedStart }],
      schema: schemaB,
      shaderSignature: 'stack-b',
    });

    await orchestrator.trigger({ params: [{ b: 0.9 }], schema: schemaB, shaderSignature: 'stack-b' });
    const rebased = await orchestrator.update(800);

    expect(rebased).not.toBeNull();
    expect(Number.isNaN(rebased!.params[0].b)).toBe(false);
    expect(rebased!.params[0].a).toBeUndefined();
  });

  test('rapid toggle on/off/on keeps exactly one active orchestrator lifecycle', async () => {
    const orchestrator = new TransitionOrchestrator({ source: 'timer', intervalMs: 1, durationMs: 1000 });
    orchestrator.start({ params: [{ a: 0 }], schema: schemaA, shaderSignature: 'a', now: 0 });
    orchestrator.stop();
    orchestrator.start({ params: [{ a: 0 }], schema: schemaA, shaderSignature: 'a', now: 0 });

    await orchestrator.trigger({ params: [{ a: 1 }], schema: schemaA, shaderSignature: 'a' });

    let previous = 0;
    for (let i = 1; i <= 100; i++) {
      const tick = await orchestrator.update(i * 10);
      if (!tick) continue;
      expect(tick.params[0].a).toBeGreaterThanOrEqual(previous);
      previous = tick.params[0].a;
    }
    expect(orchestrator.getState()).not.toBe('IDLE');
  });

  test('fp range and step boundary stay in range and settle on grid', async () => {
    const orchestrator = new TransitionOrchestrator({ source: 'timer', intervalMs: 1, durationMs: 1000 });
    orchestrator.start({ params: [{ a: 0 }], schema: schemaA, shaderSignature: 'a', now: 0 });
    await orchestrator.trigger({ params: [{ a: 1 }], schema: schemaA, shaderSignature: 'a' });

    let final = 0;
    for (let i = 1; i <= 1000; i++) {
      const tick = await orchestrator.update(i);
      if (!tick) continue;
      const value = tick.params[0].a;
      expect(value).toBeGreaterThanOrEqual(0);
      expect(value).toBeLessThanOrEqual(1);
      final = value;
    }
    expect(final).toBe(1);
  });
});
