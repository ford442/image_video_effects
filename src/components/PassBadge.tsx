import React from 'react';
import { getMultipassInfo } from '../utils/multipass';
import './PassBadge.css';

interface PassBadgeProps {
  shaderId: string;
}

/**
 * Renders a `◈ N-pass` badge for multipass shaders.
 * Renders nothing for single-pass entries (passCount ≤ 1 or no entry).
 * Apply `.pass-badge-abs` via className on the parent container for
 * absolute positioning inside a card thumbnail area.
 */
export const PassBadge: React.FC<PassBadgeProps> = React.memo(({ shaderId }) => {
  const info = getMultipassInfo(shaderId);
  if (!info) return null;

  return (
    <span
      className="pass-badge pass-badge-abs"
      title={`${info.passCount}-pass multipass shader`}
    >
      ◈ {info.passCount}-pass
    </span>
  );
});

PassBadge.displayName = 'PassBadge';
