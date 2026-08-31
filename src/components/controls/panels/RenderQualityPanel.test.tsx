import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import { RenderQualityPanel } from './RenderQualityPanel';

test('source auto-exposure toggle defaults off and fires the handler', () => {
  const onSource = jest.fn();
  render(
    <RenderQualityPanel
      qualityMode="auto"
      onQualityChange={() => {}}
      maxActiveSlots={2}
      internalResolution={512}
      scale={0.75}
      adaptive
      targetFps={60}
      sourceAutoExposure={false}
      onSourceAutoExposureChange={onSource}
    />,
  );
  const box = screen.getByTestId('source-auto-exposure-toggle');
  expect(box).not.toBeChecked();
  fireEvent.click(box);
  expect(onSource).toHaveBeenCalledWith(true);
});
