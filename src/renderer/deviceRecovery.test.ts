import { AUTO_RECOVERY_COOLDOWN_MS, DeviceRecoveryController } from './deviceRecovery';

const loss = (reason = 'unknown') => ({ kind: 'device-lost' as const, reason, message: '', at: 0 });
const settle = () => new Promise((r) => setTimeout(r, 0));

function controller(recover: jest.Mock, now = { t: 0 }) {
  const states: string[] = [];
  const onFailed = jest.fn();
  const c = new DeviceRecoveryController({
    recover,
    onStatus: (s) => states.push(s.state),
    onFailed,
    describeFailure: () => 'probe: no adapter',
    now: () => now.t,
  });
  return { c, states, onFailed, now };
}

describe('DeviceRecoveryController', () => {
  it('auto-recovers once per loss', async () => {
    const { c, states } = controller(jest.fn().mockResolvedValue(true));
    c.handleLoss(loss());
    await settle();
    expect(states).toEqual(['lost', 'recovering', 'idle']);
    expect(c.getStatus()).toMatchObject({ attempts: 1, lastRecoveredAt: 0, lastLoss: { reason: 'unknown' } });
  });

  it('fails with the probe diagnostics and recovers on retry', async () => {
    const recover = jest.fn().mockResolvedValueOnce(false).mockResolvedValueOnce(true);
    const { c, states, onFailed } = controller(recover);
    c.handleLoss(loss());
    await settle();
    expect(states).toEqual(['lost', 'recovering', 'failed']);
    expect(onFailed).toHaveBeenCalledWith('probe: no adapter');
    expect(c.getStatus().lastError).toBe('probe: no adapter');
    expect(await c.retry()).toBe(true);
    expect(c.getStatus()).toMatchObject({ state: 'idle', attempts: 2, lastError: null });
  });

  it('a throwing rebuild fails with its message', async () => {
    const { c, onFailed } = controller(jest.fn().mockRejectedValue(new Error('canvas gone')));
    expect(await c.retry()).toBe(false);
    expect(onFailed).toHaveBeenCalledWith('canvas gone');
  });

  it('is single-flight and ignores losses reported mid-recovery', async () => {
    let finish!: (ok: boolean) => void;
    const recover = jest.fn(() => new Promise<boolean>((r) => { finish = r; }));
    const { c } = controller(recover);
    const a = c.retry();
    const b = c.retry();
    c.handleLoss(loss());
    expect(recover).toHaveBeenCalledTimes(1);
    finish(true);
    expect(await a).toBe(true);
    expect(await b).toBe(true);
  });

  it('only auto-retries again once the cooldown has passed', async () => {
    const recover = jest.fn().mockResolvedValue(true);
    const { c, states, now } = controller(recover);
    c.handleLoss(loss());
    await settle();
    now.t = AUTO_RECOVERY_COOLDOWN_MS - 1;
    c.handleLoss(loss());
    await settle();
    expect(states.slice(-2)).toEqual(['lost', 'failed']);
    expect(recover).toHaveBeenCalledTimes(1);
    expect(await c.retry()).toBe(true); // manual retry is always allowed
    now.t += AUTO_RECOVERY_COOLDOWN_MS + 1;
    c.handleLoss(loss());
    await settle();
    expect(recover).toHaveBeenCalledTimes(3);
  });

  it('stops after dispose', async () => {
    const recover = jest.fn().mockResolvedValue(true);
    const { c, states } = controller(recover);
    c.dispose();
    c.handleLoss(loss());
    expect(await c.retry()).toBe(false);
    expect(recover).not.toHaveBeenCalled();
    expect(states).toEqual([]);
  });
});
