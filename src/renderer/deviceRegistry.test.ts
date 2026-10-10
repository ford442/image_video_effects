import {
  clearRendererDevice,
  getDeviceGeneration,
  getRendererDevice,
  getRendererDeviceEntry,
  isRendererDeviceLive,
  publishRendererDevice,
  resetRendererDeviceRegistryForTests,
  subscribeRendererDevice,
} from './deviceRegistry';

const fakeDevice = (label: string) => ({ label }) as unknown as GPUDevice;

describe('renderer device registry (#1395)', () => {
  beforeEach(() => resetRendererDeviceRegistryForTests());

  it('every publish and clear bumps the generation and notifies subscribers', () => {
    const seen: Array<[number, string | null]> = [];
    const unsubscribe = subscribeRendererDevice((e) => seen.push([e.generation, e.thread]));
    const g0 = getDeviceGeneration();
    const owner = {};

    publishRendererDevice(fakeDevice('a'), { owner, supportsSubgroups: true });
    expect(getRendererDevice()).toEqual({ label: 'a' });
    expect(getRendererDeviceEntry()).toMatchObject({ thread: 'main', supportsSubgroups: true });
    clearRendererDevice('device lost', owner);
    expect(getRendererDevice()).toBeNull();
    expect(getRendererDeviceEntry().clearedBecause).toBe('device lost');

    expect(seen).toEqual([[g0 + 1, 'main'], [g0 + 2, null]]);
    unsubscribe();
    publishRendererDevice(fakeDevice('b'), { owner });
    expect(seen).toHaveLength(2);
  });

  it('a worker owner is live without a page device', () => {
    publishRendererDevice(null, { thread: 'worker' });
    expect(isRendererDeviceLive()).toBe(true);
    expect(getRendererDevice()).toBeNull();
  });

  it('only the current owner can clear, and an empty clear keeps the generation', () => {
    const oldOwner = {};
    const newOwner = {};
    publishRendererDevice(fakeDevice('old'), { owner: oldOwner });
    publishRendererDevice(fakeDevice('new'), { owner: newOwner });
    const generation = getDeviceGeneration();

    clearRendererDevice('late teardown', oldOwner);
    expect(getRendererDevice()).toEqual({ label: 'new' });
    expect(getDeviceGeneration()).toBe(generation);

    clearRendererDevice('teardown', newOwner);
    clearRendererDevice('teardown again', newOwner);
    expect(getDeviceGeneration()).toBe(generation + 1);
  });

  it('a throwing subscriber does not stop the others', () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => undefined);
    const ok = jest.fn();
    subscribeRendererDevice(() => { throw new Error('boom'); });
    subscribeRendererDevice(ok);
    publishRendererDevice(fakeDevice('a'));
    expect(ok).toHaveBeenCalledTimes(1);
    warn.mockRestore();
  });
});
