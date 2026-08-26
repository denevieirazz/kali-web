import { create } from 'zustand';

interface NativeWindowBindingsState {
  sessionToWindow: Record<string, string>;
  bind: (sessionId: string, windowId: string) => void;
  unbind: (sessionId: string, windowId: string) => void;
}

export const useNativeWindowBindings = create<NativeWindowBindingsState>((set) => ({
  sessionToWindow: {},
  bind: (sessionId, windowId) => set((state) => (
    state.sessionToWindow[sessionId] === windowId
      ? state
      : { sessionToWindow: { ...state.sessionToWindow, [sessionId]: windowId } }
  )),
  unbind: (sessionId, windowId) => set((state) => {
    if (state.sessionToWindow[sessionId] !== windowId) return state;
    const next = { ...state.sessionToWindow };
    delete next[sessionId];
    return { sessionToWindow: next };
  }),
}));

