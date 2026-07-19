import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import { AdvancedDebugPanel } from './AdvancedDebugPanel';

test('renders coordinate browser button and fires onOpenCoordinateBrowser', () => {
    const onOpenCoordinateBrowser = jest.fn();

    render(
        <AdvancedDebugPanel
            onOpenCoordinateBrowser={onOpenCoordinateBrowser}
        />
    );

    fireEvent.click(screen.getByText(/Browse by Coordinate/));
    expect(onOpenCoordinateBrowser).toHaveBeenCalledTimes(1);
});

test('fires onOpenStorageBrowser when storage entry is shown', () => {
    const onOpenStorageBrowser = jest.fn();

    render(
        <AdvancedDebugPanel
            onOpenCoordinateBrowser={() => {}}
            onOpenStorageBrowser={onOpenStorageBrowser}
        />
    );

    fireEvent.click(screen.getByText(/VPS Storage Browser/));
    expect(onOpenStorageBrowser).toHaveBeenCalledTimes(1);
});
