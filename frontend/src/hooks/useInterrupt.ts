import { useEffect } from 'react';
import kernel from '../core/kernel';

/**
 * useInterrupt - Kernel Signal & Interrupt Handler
 * 
 * Captures low-level Kernel events.
 * Allows components to react to hardware or software signals,
 * such as service state changes, driver loading, or BSOD events.
 * 
 * Similar to how Windows sends WM_ messages to application windows.
 */
export function useInterrupt(event: string, callback: (...args: any[]) => void) {
  useEffect(() => {
    // Subscribe to low-level Kernel signals
    const unsub = kernel.on(event, (...args) => {
      try {
        callback(...args);
      } catch (e) {
        // App crashed while processing a critical system signal
        kernel.log('ERROR', 'InterruptHandler', `Failed to process signal ${event}: ${e}`);
      }
    });

    // Release subscription (memory management)
    return () => unsub();
  }, [event, callback]);
}

/**
 * useSystemSignals - Critical Kernel signal hub
 */
export function useSystemSignals(handlers: {
  onBsod?: (info: any) => void;
  onServiceChange?: (service: any) => void;
  onDriverChange?: (driver: any) => void;
  onLog?: (entry: any) => void;
}) {
  useInterrupt('bsod', (info) => handlers.onBsod?.(info));
  useInterrupt('serviceChange', (service) => handlers.onServiceChange?.(service));
  useInterrupt('driverChange', (driver) => handlers.onDriverChange?.(driver));
  useInterrupt('log', (entry) => handlers.onLog?.(entry));
}
