import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import { EffectCategoryPanel } from './EffectCategoryPanel';

test('renders category select and calls setShaderCategory', () => {
    const setShaderCategory = jest.fn();

    render(
        <EffectCategoryPanel
            shaderCategory="image"
            setShaderCategory={setShaderCategory}
        />
    );

    const select = screen.getByLabelText(/Effect Filter/i);
    expect(select).toBeInTheDocument();

    fireEvent.change(select, { target: { value: 'generative' } });
    expect(setShaderCategory).toHaveBeenCalledWith('generative');
});
