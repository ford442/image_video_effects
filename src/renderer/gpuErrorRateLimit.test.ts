import { createRateLimitedReporter, reportUncapturedGpuError } from './gpuErrorRateLimit';
import * as ErrorHandling from './ErrorHandling';

describe('gpuErrorRateLimit (#1311 WP-A item 5)', () => {
  it('reports the first occurrence per message and then every Nth', () => {
    const sink = jest.fn();
    const report = createRateLimitedReporter(5, sink);
    for (let i = 0; i < 12; i++) report({ type: 'shader-compile', message: 'A', recoverable: true });
    report({ type: 'shader-compile', message: 'B', recoverable: true });
    expect(sink.mock.calls.map(([e]) => e.message)).toEqual(['A', 'A (×5)', 'A (×10)', 'B']);
  });

  it('maps GPUValidationError to a recoverable shader-compile error through reportError', () => {
    const spy = jest.spyOn(ErrorHandling, 'reportError').mockImplementation(() => {});
    reportUncapturedGpuError({ name: 'GPUValidationError', message: 'unique-validation-msg' } as unknown as GPUError, 'test');
    expect(spy).toHaveBeenCalledWith(expect.objectContaining({
      type: 'shader-compile', recoverable: true, message: expect.stringContaining('unique-validation-msg'),
    }));
  });
});
