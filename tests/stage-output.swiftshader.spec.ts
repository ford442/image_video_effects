/**
 * Stage outputs (docs/STAGE_OUTPUTS.md) on a real — software — WebGPU device.
 *
 * A stage popup transfers its canvas to the control window, which hands it to the
 * renderer (render worker or page). The renderer configures it on its one device
 * and presents the program to it every frame. Compositor screenshots of WebGPU
 * canvases are blank on SwiftShader, so this checks the renderer's own output
 * status (frames presented, errors) and that no second device appears.
 *
 * Needs a production build: `npm run build && npm run test:engine2`.
 */
import { expect, test, type Page } from '@playwright/test';
import {
  installGpuUncapturedErrorHook,
  readGpuUncapturedErrors,
  startStaticServer,
  stopStaticServer,
  waitForBootDefaultShader,
} from './helpers/rendererHarness';

const PORT = 3471;
const ISOLATED = process.env.PX_ISOLATED === '1';

test.beforeAll(async () => {
  await startStaticServer(PORT, { isolated: ISOLATED });
});

test.afterAll(async () => {
  await stopStaticServer();
});

type Mode = 'main' | 'worker';

async function boot(page: Page, mode: Mode): Promise<void> {
  await installGpuUncapturedErrorHook(page);
  await page.goto(`http://localhost:${PORT}/?renderer=${mode}&testMode=1`, { waitUntil: 'load' });
  await page.waitForFunction(
    () => (window as any).webgpuProbe != null && (window as any).__pixelocity__?.renderer != null,
    null,
    { timeout: 60_000 },
  );
  const probe = await page.evaluate(() => (window as any).webgpuProbe);
  expect(probe.ok, `boot probe failed: ${probe.failedStage} ${probe.lastError}`).toBe(true);
  await waitForBootDefaultShader(page);
}

const outputStatus = (page: Page) =>
  page.evaluate(() => (window as any).__pixelocity__.renderer.getOutputBackend()?.getOutputStatus() ?? []);

for (const mode of ['worker', 'main'] as Mode[]) {
  test(`a stage window presents the program from the same device (${mode})`, async ({ page, context }) => {
    await boot(page, mode);
    await page.getByRole('button', { name: /Stage/ }).first().click();
    const popupPromise = context.waitForEvent('page');
    await page.getByRole('button', { name: 'Open stage window' }).click();
    const stage = await popupPromise;
    await stage.waitForLoadState('load');

    await expect.poll(async () => (await outputStatus(page))[0]?.framesPresented ?? 0, { timeout: 60_000 })
      .toBeGreaterThan(3);
    const [status] = await outputStatus(page);
    expect(status).toMatchObject({ id: 'stage-1', singular: false });
    expect(status.lastError).toBeUndefined();
    expect(status.width).toBeGreaterThan(1);

    // Calibration reaches the renderer; a keystone is still a valid pin.
    await stage.keyboard.press('2');
    await stage.keyboard.press('Shift+ArrowLeft');
    await stage.keyboard.press('t');
    const before = (await outputStatus(page))[0]?.framesPresented ?? 0;
    await expect.poll(async () => (await outputStatus(page))[0]?.framesPresented ?? 0, { timeout: 30_000 })
      .toBeGreaterThan(before + 2);
    expect((await outputStatus(page))[0]?.singular).toBe(false);

    // One device: the stage did not create its own.
    const diag = await page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics());
    if (mode === 'worker') expect(diag.gpuErrors ?? []).toEqual([]);
    expect(await readGpuUncapturedErrors(page)).toEqual([]);
    expect(await stage.evaluate(() => (window as any).webgpuProbe ?? null)).toBeNull();

    // Closing the window detaches the output.
    await stage.close();
    await expect.poll(async () => (await outputStatus(page)).length, { timeout: 15_000 }).toBe(0);
  });
}

for (const mode of ['worker', 'main'] as Mode[]) {
  test(`a stage re-attaches with its calibration after device-loss recovery (${mode})`, async ({ page, context }) => {
    test.setTimeout(180_000);
    await boot(page, mode);
    await page.getByRole('button', { name: /Stage/ }).first().click();
    const popupPromise = context.waitForEvent('page');
    await page.getByRole('button', { name: 'Open stage window' }).click();
    const stage = await popupPromise;
    await stage.waitForLoadState('load');
    await expect.poll(async () => (await outputStatus(page))[0]?.framesPresented ?? 0, { timeout: 60_000 })
      .toBeGreaterThan(3);
    await stage.keyboard.press('Shift+ArrowRight');

    expect(await page.evaluate(() => (window as any).__pixelocity__.simulateDeviceLoss())).toBe(true);
    await page.waitForFunction(
      () => {
        const s = (window as any).__pixelocity__.getDeviceRecoveryStatus();
        return s.state === 'idle' && s.attempts === 1;
      },
      null,
      { timeout: 90_000 },
    );
    // The new backend got a fresh canvas from the stage and presents to it.
    await expect.poll(async () => (await outputStatus(page))[0]?.framesPresented ?? 0, { timeout: 60_000 })
      .toBeGreaterThan(3);
    // The calibration survived (it lives in the control window, not the lost device).
    const corners = await page.evaluate(() => JSON.parse(localStorage.getItem('pixelocity.stageOutputs.v1') ?? '{}')['stage-1']?.corners);
    expect(corners?.[0]?.[0]).toBeGreaterThan(0);
    const diag = await page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics());
    expect(diag.liveGpuDevices ?? 1).toBe(1);
    await stage.close();
  });
}
