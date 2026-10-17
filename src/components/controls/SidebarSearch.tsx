import React from 'react';
import type { ShaderEntry } from '../../renderer/types';

export interface SidebarSearchProps {
    query: string;
    setQuery: (query: string) => void;
    effectResults: ShaderEntry[];
    activeSlot: number;
    onPickEffect: (id: string) => void;
}

export const SidebarSearch: React.FC<SidebarSearchProps> = ({
    query, setQuery, effectResults, activeSlot, onPickEffect,
}) => (
    <div className="sidebar-search">
        <div className="sidebar-search-field">
            <input
                type="search"
                className="glass-input"
                placeholder="Filter controls & effects…"
                aria-label="Filter controls and effects"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                onKeyDown={(e) => {
                    // Escape clears the filter; Enter applies the top effect hit to the active slot.
                    if (e.key === 'Escape') setQuery('');
                    else if (e.key === 'Enter' && effectResults[0]) onPickEffect(effectResults[0].id);
                    e.stopPropagation();
                }}
            />
            {query && (
                <button type="button" className="sidebar-search-clear" aria-label="Clear filter" onClick={() => setQuery('')}>
                    ✕
                </button>
            )}
        </div>
        {effectResults.length > 0 && (
            <div className="sidebar-search-results" role="listbox" aria-label={`Matching effects for slot ${activeSlot + 1}`}>
                <div className="sidebar-search-results-title">Effects → Slot {activeSlot + 1}</div>
                {effectResults.map((entry) => (
                    <button
                        key={entry.id}
                        type="button"
                        role="option"
                        aria-selected={false}
                        className="sidebar-search-result"
                        onClick={() => onPickEffect(entry.id)}
                        title={entry.description ?? entry.id}
                    >
                        {entry.name}
                    </button>
                ))}
            </div>
        )}
    </div>
);

export default SidebarSearch;
