import { useEffect, useLayoutEffect, useRef, useState, useCallback } from 'react';
import { createPortal } from 'react-dom';
import type { CSSProperties, KeyboardEvent, PointerEvent as ReactPointerEvent } from 'react';
import type { ContextMenuItem } from '../../types';
import './ContextMenu.css';

interface Props {
  x: number;
  y: number;
  items: ContextMenuItem[];
  onClose: () => void;
}

const VIEWPORT_GAP = 8;
const HOVER_DELAY_MS = 180;

interface SubmenuProps {
  anchor: HTMLElement;
  items: ContextMenuItem[];
  onClose: () => void;
  onCloseSubmenu: () => void;
  onMouseEnter: () => void;
  onMouseLeave: () => void;
}

function Submenu({ anchor, items, onClose, onCloseSubmenu, onMouseEnter, onMouseLeave }: SubmenuProps) {
  const ref = useRef<HTMLDivElement>(null);
  const [style, setStyle] = useState<CSSProperties>({ visibility: 'hidden', left: 0, top: 0 });

  useLayoutEffect(() => {
    const menu = ref.current;
    if (!menu) return;
    const a = anchor.getBoundingClientRect();
    const m = menu.getBoundingClientRect();

    // Prefer right of anchor, flip left if overflowing
    let left = a.right + 2;
    if (left + m.width > window.innerWidth - VIEWPORT_GAP) {
      left = a.left - m.width - 2;
    }
    left = Math.max(VIEWPORT_GAP, Math.min(left, window.innerWidth - m.width - VIEWPORT_GAP));

    // Align top with anchor, shift up if overflowing bottom
    let top = a.top;
    if (top + m.height > window.innerHeight - VIEWPORT_GAP) {
      top = window.innerHeight - m.height - VIEWPORT_GAP;
    }
    top = Math.max(VIEWPORT_GAP, top);

    setStyle({ left, top, visibility: 'visible' });
  }, [anchor, items]);

  const handleKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    const buttons = Array.from(
      ref.current?.querySelectorAll<HTMLButtonElement>(':scope > .context-menu-item-wrapper > button:not(:disabled)') || []
    );
    const currentIndex = buttons.indexOf(document.activeElement as HTMLButtonElement);

    if (e.key === 'Escape' || e.key === 'ArrowLeft') {
      e.preventDefault();
      e.stopPropagation();
      onCloseSubmenu();
      anchor.focus();
    } else if (e.key === 'ArrowDown') {
      e.preventDefault();
      const next = (currentIndex + 1) % buttons.length;
      buttons[next]?.focus();
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      const prev = (currentIndex - 1 + buttons.length) % buttons.length;
      buttons[prev]?.focus();
    } else if (e.key === 'Home') {
      e.preventDefault();
      buttons[0]?.focus();
    } else if (e.key === 'End') {
      e.preventDefault();
      buttons[buttons.length - 1]?.focus();
    }
  };

  return createPortal(
    <div
      ref={ref}
      className="context-submenu acrylic context-submenu-portal"
      style={style}
      role="menu"
      tabIndex={-1}
      onKeyDown={handleKeyDown}
      onPointerEnter={onMouseEnter}
      onPointerLeave={onMouseLeave}
    >
      {items.map((item, index) => (
        <Entry key={item.id || index} item={item} onClose={onClose} />
      ))}
    </div>,
    document.body
  );
}

function Entry({ item, onClose }: { item: ContextMenuItem; onClose: () => void }) {
  const buttonRef = useRef<HTMLButtonElement>(null);
  const [open, setOpen] = useState(false);
  const timerRef = useRef<number | null>(null);

  const clearTimer = () => {
    if (timerRef.current !== null) {
      window.clearTimeout(timerRef.current);
      timerRef.current = null;
    }
  };

  const handlePointerEnter = () => {
    clearTimer();
    if (item.children && !item.disabled) {
      timerRef.current = window.setTimeout(() => {
        setOpen(true);
      }, 50);
    }
  };

  const handlePointerLeave = () => {
    clearTimer();
    if (item.children) {
      timerRef.current = window.setTimeout(() => {
        setOpen(false);
      }, HOVER_DELAY_MS);
    }
  };

  useEffect(() => {
    return () => clearTimer();
  }, []);

  if (item.separator) {
    return <div className="context-menu-separator" role="separator" />;
  }

  const handleClick = () => {
    if (item.disabled) return;
    if (item.children) {
      setOpen((v) => !v);
      return;
    }
    if (item.onClick) {
      item.onClick();
      onClose();
    }
  };

  const handleKeyDown = (e: KeyboardEvent<HTMLButtonElement>) => {
    if (item.children && (e.key === 'ArrowRight' || e.key === 'Enter' || e.key === ' ')) {
      e.preventDefault();
      setOpen(true);
      requestAnimationFrame(() => {
        const firstSubItem = document.querySelector<HTMLButtonElement>(
          '.context-submenu-portal .context-menu-item:not(:disabled)'
        );
        firstSubItem?.focus();
      });
    } else if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      handleClick();
    }
  };

  return (
    <div
      className="context-menu-item-wrapper"
      onPointerEnter={handlePointerEnter}
      onPointerLeave={handlePointerLeave}
    >
      <button
        ref={buttonRef}
        type="button"
        role="menuitem"
        aria-haspopup={item.children ? 'menu' : undefined}
        aria-expanded={item.children ? open : undefined}
        aria-disabled={item.disabled}
        disabled={item.disabled}
        className={`context-menu-item ${item.disabled ? 'disabled' : ''} ${open ? 'has-open-submenu' : ''}`}
        onClick={handleClick}
        onKeyDown={handleKeyDown}
      >
        <span className="context-menu-icon" aria-hidden="true">
          {item.icon || ''}
        </span>
        <span className="context-menu-label">{item.label}</span>
        {item.shortcut && <span className="context-menu-shortcut">{item.shortcut}</span>}
        {item.children && (
          <span className="context-menu-arrow" aria-hidden="true">
            ›
          </span>
        )}
      </button>

      {open && item.children && buttonRef.current && (
        <Submenu
          anchor={buttonRef.current}
          items={item.children}
          onClose={onClose}
          onCloseSubmenu={() => setOpen(false)}
          onMouseEnter={clearTimer}
          onMouseLeave={handlePointerLeave}
        />
      )}
    </div>
  );
}

export default function ContextMenu({ x, y, items, onClose }: Props) {
  const ref = useRef<HTMLDivElement>(null);
  const previouslyFocusedElement = useRef<HTMLElement | null>(null);
  const [style, setStyle] = useState<CSSProperties>({ left: x, top: y, visibility: 'hidden' });

  useLayoutEffect(() => {
    const menu = ref.current;
    if (!menu) return;
    const r = menu.getBoundingClientRect();

    let left = x;
    if (left + r.width > window.innerWidth - VIEWPORT_GAP) {
      left = window.innerWidth - r.width - VIEWPORT_GAP;
    }
    left = Math.max(VIEWPORT_GAP, left);

    let top = y;
    if (top + r.height > window.innerHeight - VIEWPORT_GAP) {
      top = window.innerHeight - r.height - VIEWPORT_GAP;
    }
    top = Math.max(VIEWPORT_GAP, top);

    setStyle({ left, top, visibility: 'visible' });
  }, [x, y, items]);

  useEffect(() => {
    previouslyFocusedElement.current = document.activeElement as HTMLElement | null;

    const handlePointerDownOutside = (e: PointerEvent) => {
      const target = e.target as Node;
      const isInsideRoot = ref.current?.contains(target);
      const isInsideSubmenu = (target as Element).closest?.('.context-submenu-portal');
      if (!isInsideRoot && !isInsideSubmenu) {
        onClose();
      }
    };

    const handleWindowChange = () => {
      onClose();
    };

    document.addEventListener('pointerdown', handlePointerDownOutside, true);
    window.addEventListener('resize', handleWindowChange);
    window.addEventListener('blur', handleWindowChange);

    requestAnimationFrame(() => {
      ref.current?.querySelector<HTMLButtonElement>('.context-menu-item:not(:disabled)')?.focus();
    });

    return () => {
      document.removeEventListener('pointerdown', handlePointerDownOutside, true);
      window.removeEventListener('resize', handleWindowChange);
      window.removeEventListener('blur', handleWindowChange);
      if (previouslyFocusedElement.current && document.body.contains(previouslyFocusedElement.current)) {
        previouslyFocusedElement.current.focus();
      }
    };
  }, [onClose]);

  const handleKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    const buttons = Array.from(
      ref.current?.querySelectorAll<HTMLButtonElement>(':scope > .context-menu-item-wrapper > button:not(:disabled)') || []
    );
    const currentIndex = buttons.indexOf(document.activeElement as HTMLButtonElement);

    if (e.key === 'Escape') {
      e.preventDefault();
      onClose();
    } else if (e.key === 'ArrowDown') {
      e.preventDefault();
      const next = (currentIndex + 1) % buttons.length;
      buttons[next]?.focus();
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      const prev = (currentIndex - 1 + buttons.length) % buttons.length;
      buttons[prev]?.focus();
    } else if (e.key === 'Home') {
      e.preventDefault();
      buttons[0]?.focus();
    } else if (e.key === 'End') {
      e.preventDefault();
      buttons[buttons.length - 1]?.focus();
    }
  };

  return createPortal(
    <div
      ref={ref}
      className="context-menu acrylic context-menu-portal"
      style={style}
      role="menu"
      tabIndex={-1}
      onKeyDown={handleKeyDown}
    >
      {items.map((item, index) => (
        <Entry key={item.id || index} item={item} onClose={onClose} />
      ))}
    </div>,
    document.body
  );
}
