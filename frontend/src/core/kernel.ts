// CloudOS kernel facade.
//
// The original kernel implementation is kept in kernelLegacy.ts while the core is
// being split into focused managers. Every consumer imports this module, so fixes
// and lifecycle guards can be installed once without spreading compatibility code
// across React components.

export * from './kernelLegacy';

import kernel from './kernelLegacy';
import { installKernelHardening } from './kernelHardening';

installKernelHardening(kernel);

export { kernel };
export default kernel;
