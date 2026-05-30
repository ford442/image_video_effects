import { easeInOutSine, lerpParamMap, ParamMap, ParamMapSchema, snapToStep } from '../utils/transitionMath';

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

export interface TransitionTickResult {
  params: ParamMap[];
  settled: boolean;
  progress: number;
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

    if (linearProgress >= 1) {
      const snapped = snapMapsToSchema(this.targetParams, this.schema);
      this.currentParams = snapped;
      this.startParams = cloneMaps(snapped);
      this.targetParams = cloneMaps(snapped);
      this.state = 'WAITING';
      this.waitingElapsed = 0;
      this.transitionElapsed = 0;
      return { params: cloneMaps(snapped), settled: true, progress: 1 };
    }

    return { params: cloneMaps(next), settled: false, progress: linearProgress };
  }

  private beginTransition(target: TransitionTarget) {
    if (target.schema) this.schema = target.schema;
    if (target.shaderSignature) this.shaderSignature = target.shaderSignature;

    const snappedTarget = snapMapsToSchema(target.params, this.schema);
    this.startParams = cloneMaps(this.currentParams);
    this.targetParams = cloneMaps(snappedTarget);
    this.transitionElapsed = 0;
    this.waitingElapsed = 0;
    this.state = 'TRANSITIONING';
  }

  private consumeBeatInWindow(windowStart: number, windowEnd: number): boolean {
    let consumed = false;
    while (this.beats.length > 0) {
      const beatTs = this.beats[0];
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
