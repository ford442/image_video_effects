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

test('Display P3 toggle defaults off, shows the status, and fires the handler', () => {
  const onP3 = jest.fn();
  render(
    <RenderQualityPanel
      qualityMode="auto"
      onQualityChange={() => {}}
      maxActiveSlots={2}
      internalResolution={512}
      scale={0.75}
      adaptive
      targetFps={60}
      displayP3={false}
      onDisplayP3Change={onP3}
      displayP3Status="Using sRGB: this browser/display rejected Display P3"
    />,
  );
  const box = screen.getByTestId('display-p3-toggle');
  expect(box).not.toBeChecked();
  expect(screen.getByTestId('display-p3-status')).toHaveTextContent('Using sRGB');
  fireEvent.click(box);
  expect(onP3).toHaveBeenCalledWith(true);
});

test('Display P3 toggle is disabled off the WebGPU backend', () => {
  render(
    <RenderQualityPanel
      qualityMode="auto"
      onQualityChange={() => {}}
      maxActiveSlots={2}
      internalResolution={512}
      scale={0.75}
      adaptive
      targetFps={60}
      onDisplayP3Change={() => {}}
      displayP3Disabled
    />,
  );
  expect(screen.getByTestId('display-p3-toggle')).toBeDisabled();
});
