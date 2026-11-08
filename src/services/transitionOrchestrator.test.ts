import { easeInOutSine } from '../utils/transitionMath';
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
    expect(result!.params[0]!.a).toBeLessThanOrEqual(1);
  });

  test('schema change mid-transition rebases safely with no NaN', async () => {
    const orchestrator = new TransitionOrchestrator({ source: 'timer', intervalMs: 1000, durationMs: 1000 });
    orchestrator.start({ params: [{ a: 0 }], schema: schemaA, shaderSignature: 'stack-a', now: 0 });

    await orchestrator.trigger({ params: [{ a: 1 }], schema: schemaA, shaderSignature: 'stack-a' });
    const at40 = await orchestrator.update(400);
    expect(at40).not.toBeNull();

    const rebasedStart = at40!.params[0]!.a;
    expect(rebasedStart).toBeDefined();
    orchestrator.setBaseline({
      params: [{ b: rebasedStart! }],
      schema: schemaB,
      shaderSignature: 'stack-b',
    });

    await orchestrator.trigger({ params: [{ b: 0.9 }], schema: schemaB, shaderSignature: 'stack-b' });
    const rebased = await orchestrator.update(800);

    expect(rebased).not.toBeNull();
    expect(Number.isNaN(rebased!.params[0]!.b)).toBe(false);
    expect(rebased!.params[0]!.a).toBeUndefined();
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
      const a = tick.params[0]!.a;
      expect(a).toBeGreaterThanOrEqual(previous);
      previous = a!;
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
      const value = tick.params[0]!.a;
      expect(value).toBeGreaterThanOrEqual(0);
      expect(value).toBeLessThanOrEqual(1);
      final = value!;
    }
    expect(final).toBe(1);
  });

  describe('picture hold', () => {
    const start = (durationMs: number) => {
      const orchestrator = new TransitionOrchestrator({ source: 'timer', intervalMs: 1_000_000, durationMs });
      orchestrator.start({ params: [{ a: 0 }], schema: schemaA, shaderSignature: 'stack-a', now: 0 });
      return orchestrator;
    };
    const runTicks = async (orchestrator: TransitionOrchestrator, untilMs: number, stepMs = 100) => {
      const ticks = [];
      for (let t = stepMs; t <= untilMs; t += stepMs) {
        const tick = await orchestrator.update(t);
        if (tick) ticks.push(tick);
      }
      return ticks;
    };

    test('param-only ticks never request a hold and never mix', async () => {
      const orchestrator = start(1000);
      expect(orchestrator.requestHold('stack-a')).toBeNull();
      await orchestrator.trigger({ params: [{ a: 1 }], schema: schemaA, shaderSignature: 'stack-a' });

      const ticks = await runTicks(orchestrator, 1200);
      expect(ticks.length).toBeGreaterThan(5);
      expect(ticks.every((t) => t.hold === null)).toBe(true);
      expect(ticks.every((t) => t.mix === 0)).toBe(true);
      // The sliders still ease in between.
      const middle = ticks.find((t) => t.progress > 0.4 && t.progress < 0.6)!;
      expect(middle.params[0]!.a).toBeGreaterThan(0);
      expect(middle.params[0]!.a).toBeLessThan(1);
    });

    test('a transition without a signature is param-only too', async () => {
      const orchestrator = start(1000);
      await orchestrator.trigger({ params: [{ a: 1 }], schema: schemaA });
      const ticks = await runTicks(orchestrator, 1200);
      expect(ticks.every((t) => t.hold === null && t.mix === 0)).toBe(true);
    });

    test('a shader-signature change requests exactly one hold, on its first tick', async () => {
      const orchestrator = start(1000);
      expect(orchestrator.requestHold('stack-b')).toEqual({ durationMs: 1000 });
      await orchestrator.trigger({ params: [{ b: 0.8 }], schema: schemaB, shaderSignature: 'stack-b' });

      const ticks = await runTicks(orchestrator, 1200);
      const holds = ticks.filter((t) => t.hold !== null);
      expect(holds).toHaveLength(1);
      expect(holds[0]).toBe(ticks[0]);
      expect(holds[0]!.hold).toEqual({ durationMs: 1000 });
    });

    test('the dissolve carries the cue: mix follows the eased progress, params jump to the target', async () => {
      const orchestrator = start(1000);
      await orchestrator.trigger({ params: [{ b: 0.8 }], schema: schemaB, shaderSignature: 'stack-b' });

      const ticks = await runTicks(orchestrator, 1200);
      const live = ticks.filter((t) => !t.settled);
      for (const tick of live) {
        expect(tick.mix).toBeCloseTo(1 - easeInOutSine(tick.progress), 12);
        // Param maps of two stacks are never lerped.
        expect(tick.params[0]!.b).toBeCloseTo(0.8, 12);
        expect(tick.params[0]!.a).toBeUndefined();
      }
      const mixes = live.map((t) => t.mix);
      expect([...mixes].sort((x, y) => y - x)).toEqual(mixes);
      expect(mixes[0]).toBeGreaterThan(0.9);
      const last = ticks[ticks.length - 1]!;
      expect(last.settled).toBe(true);
      expect(last.mix).toBe(0);
    });

    test('a hard cut (duration 0) and a signature-less target never hold', async () => {
      const orchestrator = start(0);
      expect(orchestrator.requestHold('stack-b')).toBeNull();
      await orchestrator.trigger({ params: [{ b: 0.8 }], schema: schemaB, shaderSignature: 'stack-b' });
      const ticks = await runTicks(orchestrator, 50, 10);
      expect(ticks.every((t) => t.hold === null && t.mix === 0)).toBe(true);
    });

    test('the next transition after a dissolve is param-only again', async () => {
      const orchestrator = start(500);
      await orchestrator.trigger({ params: [{ b: 0.8 }], schema: schemaB, shaderSignature: 'stack-b' });
      const first = await runTicks(orchestrator, 700);
      expect(first.some((t) => t.hold !== null)).toBe(true);

      await orchestrator.trigger({ params: [{ b: 0.2 }], schema: schemaB, shaderSignature: 'stack-b' });
      const second = await runTicks(orchestrator, 1500);
      expect(second.length).toBeGreaterThan(0);
      expect(second.every((t) => t.hold === null && t.mix === 0)).toBe(true);
    });

    test('a baseline reset drops a hold that was not delivered yet', async () => {
      const orchestrator = start(1000);
      await orchestrator.trigger({ params: [{ b: 0.8 }], schema: schemaB, shaderSignature: 'stack-b' });
      orchestrator.setBaseline({ params: [{ b: 0.5 }], schema: schemaB, shaderSignature: 'stack-b' });
      const ticks = await runTicks(orchestrator, 200);
      expect(ticks.every((t) => t.hold === null)).toBe(true);
    });
  });
});

