import { useState, useEffect } from 'react';
import kernel from '../core/kernel';

/**
 * useKernelResource - System Call API (Sysinfo)
 * 
 * This hook is an official Kernel Subscriber. It connects to the 
 * resource scheduling engine and reflects the actual state of 
 * CPU, RAM, and Uptime as managed by the core.
 */
export function useKernelResource() {
  const [resources, setResources] = useState(kernel.resources);

  useEffect(() => {
    // Listen for memory allocation changes (e.g. process memory usage)
    const unsubMemory = kernel.on('memoryChange', (newRes) => {
      setResources({ ...newRes });
    });

    // Listen for global resource scheduler ticks
    const unsubTick = kernel.on('resourceTick', () => {
      setResources(kernel.resources);
    });

    // Listen for CPU load balancing changes
    const unsubCpu = kernel.on('cpuChange', (newRes) => {
      setResources({ ...newRes });
    });

    return () => {
      unsubMemory();
      unsubTick();
      unsubCpu();
    };
  }, []);

  return resources;
}
