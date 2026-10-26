import { crossfadeMix, easeInOutSine, lerpParamMap, ParamMap, ParamMapSchema, snapToStep } from '../utils/transitionMath';

type OrchestratorState = 'IDLE' | 'WAITING' | 'TRANSITIONING';

export interface TransitionSchemaSlot {
  params: ParamMapSchema;
}

export interface TransitionOrchestratorConfig {
  source: 'timer' | 'beat';
  intervalMs?: number;
  durationMs: number;
  easing?: (x: number) => number;
}

export interface TransitionTarget {
  params: ParamMap[];
  schema?: TransitionSchemaSlot[];
  shaderSignature?: string;
}

/** A cue that changes shader identity needs the outgoing picture frozen for this long. */
export interface TransitionHoldRequest {
  durationMs: number;
}

export interface TransitionTickResult {
  params: ParamMap[];
  settled: boolean;
  progress: number;
  /**
   * Weight of the frozen outgoing picture (1 = hold, 0 = live): `progress` through the
   * easing, run backwards (crossfadeMix). 0 unless this transition changes shader identity.
   */
  mix: number;
  /** Set on exactly one tick: the first of a transition that changes shader identity. */
  hold: TransitionHoldRequest | null;
}

const cloneMaps = (maps: ParamMap[]): ParamMap[] => maps.map((m) => ({ ...m }));
const DEFAULT_TIMER_INTERVAL_MS = 4000;
const MIN_TRANSITION_DURATION_MS = 1;

const snapMapsToSchema = (maps: ParamMap[], schema: TransitionSchemaSlot[]): ParamMap[] =>
  maps.map((map, index) => {
    const rules = schema[index]?.params || {};
    const out: ParamMap = {};
    for (const [key, value] of Object.entries(map)) {
      const rule = rules[key];
      if (!rule) {
        out[key] = value;
        continue;
      }
      out[key] = snapToStep(value, rule.min, rule.max, rule.step);
    }
    return out;
  });

export class TransitionOrchestrator {
  private config: TransitionOrchestratorConfig;
  private state: OrchestratorState = 'IDLE';
  private waitingElapsed = 0;
  private transitionElapsed = 0;
  private previousNow: number | null = null;
  private currentParams: ParamMap[] = [];
  private startParams: ParamMap[] = [];
  private targetParams: ParamMap[] = [];
  private schema: TransitionSchemaSlot[] = [];
  private shaderSignature = '';
  /** The running transition changes shader identity: its picture dissolves, its params jump. */
  private dissolving = false;
  private holdPending = false;
  private beats: number[] = [];
  private readonly maxBeats = 64;
  private targetFactory: (() => TransitionTarget | null | Promise<TransitionTarget | null>) | null = null;
  private pendingFactoryCall = false;

  constructor(config: TransitionOrchestratorConfig) {
    this.config = config;
  }

  public setTargetFactory(factory: () => TransitionTarget | null | Promise<TransitionTarget | null>) {
    this.targetFactory = factory;
  }

  public start(initial: { params: ParamMap[]; schema: TransitionSchemaSlot[]; shaderSignature: string; now?: number }) {
    this.currentParams = cloneMaps(initial.params);
    this.startParams = cloneMaps(initial.params);
    this.targetParams = cloneMaps(initial.params);
    this.schema = initial.schema;
    this.shaderSignature = initial.shaderSignature;
    this.state = 'WAITING';
    this.waitingElapsed = 0;
    this.transitionElapsed = 0;
    this.previousNow = initial.now ?? null;
    this.beats = [];
    this.pendingFactoryCall = false;
  }

  public stop() {
    this.state = 'IDLE';
    this.dissolving = false;
    this.holdPending = false;
    this.waitingElapsed = 0;
    this.transitionElapsed = 0;
    this.previousNow = null;
    this.beats = [];
    this.pendingFactoryCall = false;
  }

  public setBaseline(next: { params: ParamMap[]; schema: TransitionSchemaSlot[]; shaderSignature: string }) {
    this.currentParams = cloneMaps(next.params);
    this.startParams = cloneMaps(next.params);
    this.targetParams = cloneMaps(next.params);
    this.schema = next.schema;
    this.shaderSignature = next.shaderSignature;
    this.dissolving = false;
    this.holdPending = false;
    this.transitionElapsed = 0;
    this.waitingElapsed = 0;
    if (this.state !== 'IDLE') {
      this.state = 'WAITING';
    }
  }

  public enqueueBeat(timestamp: number) {
    this.beats.push(timestamp);
    if (this.beats.length > this.maxBeats) {
      this.beats.shift();
    }
  }

  public getCurrentParams(): ParamMap[] {
    return cloneMaps(this.currentParams);
  }

  public getShaderSignature(): string {
    return this.shaderSignature;
  }

  public getState(): OrchestratorState {
    return this.state;
  }

  public updateConfig(config: TransitionOrchestratorConfig) {
    this.config = config;
  }

  /**
   * What a cue to `shaderSignature` needs from the picture. Sliders ease on their own, so a
   * param-only cue (same signature) needs nothing; a new shader identity needs the outgoing
   * picture held for the transition duration. A duration of 0 is a hard cut: no hold.
   */
  public requestHold(shaderSignature: string | undefined): TransitionHoldRequest | null {
    if (!shaderSignature || shaderSignature === this.shaderSignature) return null;
    const durationMs = this.config.durationMs;
    return durationMs > 0 ? { durationMs } : null;
  }

  public async trigger(target?: TransitionTarget): Promise<boolean> {
    if (this.state === 'IDLE') return false;
    const resolved = target ?? (this.targetFactory ? await this.targetFactory() : null);
    if (!resolved) return false;
    this.beginTransition(resolved);
    return true;
  }

  public async update(now: number): Promise<TransitionTickResult | null> {
    if (this.state === 'IDLE') return null;
    if (this.previousNow === null) {
      this.previousNow = now;
      return null;
    }
    const dt = Math.max(0, now - this.previousNow);
    this.previousNow = now;

    if (this.state === 'WAITING') {
      this.waitingElapsed += dt;
      const shouldTriggerByTimer =
        this.config.source === 'timer' && this.waitingElapsed >= Math.max(MIN_TRANSITION_DURATION_MS, this.config.intervalMs ?? DEFAULT_TIMER_INTERVAL_MS);
      const shouldTriggerByBeat = this.config.source === 'beat' && this.consumeBeatInWindow(now - dt, now);

      if ((shouldTriggerByTimer || shouldTriggerByBeat) && this.targetFactory && !this.pendingFactoryCall) {
        this.pendingFactoryCall = true;
        const target = await this.targetFactory();
        this.pendingFactoryCall = false;
        if (target) {
          this.beginTransition(target);
        } else {
          this.waitingElapsed = 0;
        }
      }
    }

    if (this.state !== 'TRANSITIONING') {
      return null;
    }

    this.transitionElapsed += dt;
    const durationMs = Math.max(MIN_TRANSITION_DURATION_MS, this.config.durationMs);
    const linearProgress = Math.max(0, Math.min(1, this.transitionElapsed / durationMs));
    const easing = this.config.easing || easeInOutSine;
    const easedProgress = easing(linearProgress);

    const next = this.startParams.map((startMap, index) =>
      lerpParamMap(startMap, this.targetParams[index] || {}, easedProgress, this.schema[index]?.params || {})
    );
    this.currentParams = next;

    // One hold per transition, on its first tick; the picture then dissolves with the same curve.
    const hold = this.holdPending ? { durationMs: this.config.durationMs } : null;
    this.holdPending = false;

    if (linearProgress >= 1) {
      const snapped = snapMapsToSchema(this.targetParams, this.schema);
      this.currentParams = snapped;
      this.startParams = cloneMaps(snapped);
      this.targetParams = cloneMaps(snapped);
      this.state = 'WAITING';
      this.dissolving = false;
      this.waitingElapsed = 0;
      this.transitionElapsed = 0;
      return { params: cloneMaps(snapped), settled: true, progress: 1, mix: 0, hold };
    }

    const mix = this.dissolving ? crossfadeMix(linearProgress, easing) : 0;
    return { params: cloneMaps(next), settled: false, progress: linearProgress, mix, hold };
  }

  private beginTransition(target: TransitionTarget) {
    // Decided against the signature the transition leaves, before it is replaced below.
    const hold = this.requestHold(target.shaderSignature);
    if (target.schema) this.schema = target.schema;
    if (target.shaderSignature) this.shaderSignature = target.shaderSignature;

    const snappedTarget = snapMapsToSchema(target.params, this.schema);
    this.dissolving = hold !== null;
    this.holdPending = hold !== null;
    // Param maps of two different stacks cannot be lerped; the dissolve carries that cue.
    this.startParams = cloneMaps(this.dissolving ? snappedTarget : this.currentParams);
    this.targetParams = cloneMaps(snappedTarget);
    this.transitionElapsed = 0;
    this.waitingElapsed = 0;
    this.state = 'TRANSITIONING';
  }

  private consumeBeatInWindow(windowStart: number, windowEnd: number): boolean {
    let consumed = false;
    while (this.beats.length > 0) {
      const beatTs = this.beats[0]!;
      if (beatTs < windowStart) {
        this.beats.shift();
        continue;
      }
      if (beatTs <= windowEnd) {
        this.beats.shift();
        consumed = true;
      }
      break;
    }
    return consumed;
  }
}
