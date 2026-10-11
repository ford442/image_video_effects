import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom';
import ShaderScanner from './ShaderScanner';
import { fetchShaderWgsl } from '../utils/fetchShaderWgsl';
import { ShaderEntry } from '../renderer/types';
import {
  publishRendererDevice,
  resetRendererDeviceRegistryForTests,
} from '../renderer/deviceRegistry';

jest.mock('../utils/fetchShaderWgsl', () => ({
  fetchShaderWgsl: jest.fn().mockResolvedValue('@compute @workgroup_size(16, 16) fn main() {}'),
}));

describe('ShaderScanner device policy', () => {
  const requestAdapter = jest.fn();
  const requestDevice = jest.fn();

  beforeEach(() => {
    resetRendererDeviceRegistryForTests();
    window.webgpuProbe = {
      ok: true,
      finishedAt: new Date().toISOString(),
      userAgent: 'test',
      userAgentBrands: [],
      attempts: [],
    };

    const mockDevice = {
      createShaderModule: jest.fn().mockReturnValue({
        getCompilationInfo: jest.fn().mockResolvedValue({ messages: [] }),
      }),
      features: new Set(['subgroups']),
    } as unknown as GPUDevice;
    publishRendererDevice(mockDevice, { supportsSubgroups: true });

    const nav = navigator as unknown as {
      gpu?: { requestAdapter: typeof requestAdapter; requestDevice: typeof requestDevice };
    };
    nav.gpu = { requestAdapter, requestDevice };
  });

  afterEach(() => {
    delete window.webgpuProbe;
    resetRendererDeviceRegistryForTests();
  });

  it('never calls requestAdapter or requestDevice when the renderer device is registered', async () => {
    const shaders: ShaderEntry[] = [
      { id: 'test-shader', name: 'Test', url: 'shaders/test.wgsl', category: 'image' },
    ];

    render(<ShaderScanner shaders={shaders} isOpen onClose={() => {}} />);
    fireEvent.click(screen.getByRole('button', { name: /Start Scan/i }));

    await waitFor(() => {
      expect(screen.getByText(/Test/)).toBeInTheDocument();
    });

    expect(requestAdapter).not.toHaveBeenCalled();
    expect(requestDevice).not.toHaveBeenCalled();
  });
});

describe('ShaderScanner across a device loss (#1395)', () => {
  beforeEach(() => {
    (fetchShaderWgsl as jest.Mock).mockResolvedValue('@compute @workgroup_size(16, 16) fn main() {}');
    resetRendererDeviceRegistryForTests();
    window.webgpuProbe = { ok: true, finishedAt: '', userAgent: 'test', userAgentBrands: [], attempts: [] };
  });

  afterEach(() => {
    delete window.webgpuProbe;
    resetRendererDeviceRegistryForTests();
  });

  const deviceWith = (compile: () => Promise<{ messages: unknown[] }>) =>
    ({
      createShaderModule: jest.fn().mockReturnValue({ getCompilationInfo: jest.fn(compile) }),
      features: new Set<string>(),
    }) as unknown as GPUDevice & { createShaderModule: jest.Mock };

  it('re-compiles on the recovered device when the device changed mid-compile', async () => {
    const recovered = deviceWith(async () => ({ messages: [] }));
    const lost = deviceWith(async () => {
      // The device is lost and recovery publishes a new one while this compile is in flight.
      publishRendererDevice(recovered);
      throw new Error('device lost');
    });
    publishRendererDevice(lost);

    render(
      <ShaderScanner
        shaders={[{ id: 'test-shader', name: 'Test', url: 'shaders/test.wgsl', category: 'image' }]}
        isOpen
        onClose={() => {}}
      />,
    );
    fireEvent.click(screen.getByRole('button', { name: /Start Scan/i }));
    await waitFor(() => expect(recovered.createShaderModule).toHaveBeenCalledTimes(1));
    await waitFor(() => expect(screen.getByRole('button', { name: /Start Scan/i })).toBeEnabled());
    expect(lost.createShaderModule).toHaveBeenCalledTimes(1);
    expect(screen.queryByText(/device lost/)).not.toBeInTheDocument();
  });
});

describe('ShaderScanner thumbnail batch', () => {
  const realFetch = global.fetch;
  const shaders: ShaderEntry[] = [
    { id: 'fresh-one', name: 'Fresh One', url: 'shaders/fresh-one.wgsl', category: 'image' },
    { id: 'changed-one', name: 'Changed One', url: 'shaders/changed-one.wgsl', category: 'image' },
    { id: 'skipped-one', name: 'Skipped One', url: 'shaders/skipped-one.wgsl', category: 'image' },
  ];

  beforeEach(() => {
    // CRA's resetMocks clears the module-factory implementation before each test.
    (fetchShaderWgsl as jest.Mock).mockResolvedValue('@compute @workgroup_size(16, 16) fn main() {}');
    resetRendererDeviceRegistryForTests();
    window.webgpuProbe = {
      ok: true,
      finishedAt: new Date().toISOString(),
      userAgent: 'test',
      userAgentBrands: [],
      attempts: [],
    };
    publishRendererDevice({
      createShaderModule: jest.fn().mockReturnValue({
        getCompilationInfo: jest.fn().mockResolvedValue({ messages: [] }),
      }),
      features: new Set(['subgroups']),
    } as unknown as GPUDevice, { supportsSubgroups: true });

    const files: Record<string, unknown> = {
      './thumbnails/source-hashes.json': {
        generated_at: '',
        algorithm: 'test',
        upgrades: {},
        hashes: { 'fresh-one': 'h1', 'changed-one': 'h2-new', 'skipped-one': 'h3' },
        skip: ['skipped-one'],
      },
      './thumbnails/manifest.json': {
        'fresh-one': { thumbnail_url: 'thumbnails/fresh-one.png', generated_at: '', source_hash: 'h1' },
        'changed-one': { thumbnail_url: 'thumbnails/changed-one.png', generated_at: '', source_hash: 'h2-old' },
      },
    };
    global.fetch = jest.fn(async (url: RequestInfo | URL) => {
      const body = files[String(url)];
      return { ok: body !== undefined, json: async () => body } as Response;
    }) as typeof fetch;
  });

  afterEach(() => {
    global.fetch = realFetch;
    delete window.webgpuProbe;
    resetRendererDeviceRegistryForTests();
  });

  it('"changed" scope scans only stale/missing shaders and leaves out skip-allowlisted ids', async () => {
    render(<ShaderScanner shaders={shaders} isOpen onClose={() => {}} />);
    await screen.findByText(/Changed since last thumbnail \(1\)/);

    fireEvent.click(screen.getByRole('button', { name: /Start Scan/i }));
    await screen.findByText('Changed One');
    await waitFor(() => expect(screen.getByRole('button', { name: /Start Scan/i })).toBeEnabled());
    expect(screen.queryByText('Fresh One')).not.toBeInTheDocument();
    expect(screen.queryByText('Skipped One')).not.toBeInTheDocument();
  });

  function hostThatStopsOn(stopAfterCaptures: number | null) {
    const restore = jest.fn().mockResolvedValue(undefined);
    let captures = 0;
    const host = {
      // null renderer → every capture fails fast with gpu_unavailable (no GPU in jsdom).
      getRenderer: jest.fn(() => {
        captures++;
        if (stopAfterCaptures !== null && captures === stopAfterCaptures) {
          fireEvent.click(screen.getByRole('button', { name: /Stop/i }));
        }
        return null;
      }),
      loadIntoSlot: jest.fn().mockResolvedValue(undefined),
      clearSlot: jest.fn().mockResolvedValue(undefined),
      beginSession: jest.fn().mockResolvedValue(restore),
    };
    return { host, restore };
  }

  async function runRenderCheck(host: ReturnType<typeof hostThatStopsOn>['host']) {
    render(<ShaderScanner shaders={shaders} isOpen onClose={() => {}} thumbnailHost={host} />);
    fireEvent.change(screen.getByDisplayValue(/Render \+ save thumbnails/), { target: { value: 'check' } });
    fireEvent.change(screen.getByDisplayValue(/Changed since last thumbnail/), { target: { value: 'all' } });
    fireEvent.click(screen.getByRole('button', { name: /Start Scan/i }));
    await waitFor(() => expect(screen.getByRole('button', { name: /Start Scan/i })).toBeEnabled());
  }

  it('render check wraps the run in one session and restores the user stack', async () => {
    const { host, restore } = hostThatStopsOn(null);
    await runRenderCheck(host);
    expect(host.beginSession).toHaveBeenCalledTimes(1);
    expect(host.getRenderer).toHaveBeenCalledTimes(3);
    expect(restore).toHaveBeenCalledTimes(1);
    expect(screen.getAllByText('broken')).toHaveLength(3);
  });

  it('Stop mid-render still restores the user stack before the scan reports finished', async () => {
    const { host, restore } = hostThatStopsOn(1);
    await runRenderCheck(host);
    expect(host.getRenderer).toHaveBeenCalledTimes(1);
    expect(restore).toHaveBeenCalledTimes(1);
  });
});
