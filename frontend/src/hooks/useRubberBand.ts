// ============================================
// useRubberBand — Rubber band (lasso) selection
// ============================================
import { useRef, useState, useCallback } from 'react';

export interface SelectionRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

interface RubberBandOptions {
  /** Called every time the selection rect changes with the list of item keys that intersect */
  onSelectionChange: (keys: string[]) => void;
  /** Returns a map of key → DOMRect for all selectable items */
  getItemRects: () => Map<string, DOMRect>;
  /** Minimum drag distance in px before selection starts */
  threshold?: number;
}

export function useRubberBand({ onSelectionChange, getItemRects, threshold = 4 }: RubberBandOptions) {
  const [selectionRect, setSelectionRect] = useState<SelectionRect | null>(null);
  const originRef = useRef<{ x: number; y: number } | null>(null);
  const containerRef = useRef<HTMLElement | null>(null);
  const activeRef = useRef(false);

  const getContainerOffset = () => {
    if (!containerRef.current) return { left: 0, top: 0 };
    const r = containerRef.current.getBoundingClientRect();
    return { left: r.left, top: r.top };
  };

  const rectsIntersect = (a: SelectionRect, b: DOMRect, offset: { left: number; top: number }) => {
    // Convert selection rect (relative to container) to page coords
    const ax1 = a.x + offset.left;
    const ay1 = a.y + offset.top;
    const ax2 = ax1 + a.width;
    const ay2 = ay1 + a.height;
    return !(b.right < ax1 || b.left > ax2 || b.bottom < ay1 || b.top > ay2);
  };

  const onMouseDown = useCallback((e: React.MouseEvent) => {
    // Only left button, not on interactive elements
    if (e.button !== 0) return;
    const target = e.target as HTMLElement;
    if (target.closest('button, a, input, [data-no-select]')) return;

    const offset = getContainerOffset();
    originRef.current = { x: e.clientX - offset.left, y: e.clientY - offset.top };
    activeRef.current = false;

    const onMove = (me: MouseEvent) => {
      if (!originRef.current) return;
      const ox = originRef.current.x;
      const oy = originRef.current.y;
      const cx = me.clientX - offset.left;
      const cy = me.clientY - offset.top;

      const dx = cx - ox;
      const dy = cy - oy;

      if (!activeRef.current && Math.abs(dx) < threshold && Math.abs(dy) < threshold) return;
      activeRef.current = true;

      const rect: SelectionRect = {
        x: Math.min(ox, cx),
        y: Math.min(oy, cy),
        width: Math.abs(dx),
        height: Math.abs(dy),
      };
      setSelectionRect(rect);

      // Hit-test items
      const itemRects = getItemRects();
      const selected: string[] = [];
      itemRects.forEach((domRect, key) => {
        if (rectsIntersect(rect, domRect, offset)) selected.push(key);
      });
      onSelectionChange(selected);
    };

    const onUp = () => {
      originRef.current = null;
      activeRef.current = false;
      setSelectionRect(null);
      window.removeEventListener('mousemove', onMove);
      window.removeEventListener('mouseup', onUp);
    };

    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup', onUp);
  }, [getItemRects, onSelectionChange, threshold]);

  return { selectionRect, onMouseDown, containerRef };
}
