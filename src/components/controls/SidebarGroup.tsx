import React from 'react';
import { usePersistedToggle } from '../../hooks/usePersistedToggle';

export interface SidebarGroupProps {
    id: string;
    title: string;
    icon?: string;
    /** Open the group regardless of its saved state (used while filtering). */
    forceOpen?: boolean;
    defaultOpen?: boolean;
    children: React.ReactNode;
}

export const SidebarGroup: React.FC<SidebarGroupProps> = ({
    id, title, icon, forceOpen = false, defaultOpen = true, children,
}) => {
    const [open, setOpen] = usePersistedToggle(`sidebar.group.${id}`, defaultOpen);
    const expanded = open || forceOpen;
    const bodyId = `sidebar-group-${id}`;
    return (
        <section className={`sidebar-group${expanded ? ' open' : ''}`} data-group={id}>
            <button
                type="button"
                className="sidebar-group-header"
                aria-expanded={expanded}
                aria-controls={bodyId}
                onClick={() => setOpen(o => !o)}
            >
                <span>{icon ? `${icon} ` : ''}{title}</span>
                <span className="sidebar-group-chevron" aria-hidden="true">▼</span>
            </button>
            {expanded && (
                <div id={bodyId} className="sidebar-group-body">
                    {children}
                </div>
            )}
        </section>
    );
};

export default SidebarGroup;
