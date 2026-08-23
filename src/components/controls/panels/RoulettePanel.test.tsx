import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import { RoulettePanel } from './RoulettePanel';

test('renders randomize-all button and menubar hint for per-slot randomize', () => {
    const onRandomizeAllSlots = jest.fn();

    render(
        <RoulettePanel
            activeSlot={1}
            onRandomizeAllSlots={onRandomizeAllSlots}
        />
    );

    expect(screen.getByText(/Slot 2 randomize is in the menubar/i)).toBeInTheDocument();
    expect(screen.getByText(/Randomize All Slots/)).toBeInTheDocument();

    fireEvent.click(screen.getByText(/Randomize All Slots/));
    expect(onRandomizeAllSlots).toHaveBeenCalledTimes(1);
});
