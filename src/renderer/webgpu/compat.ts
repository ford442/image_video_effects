/**
 * compat.ts
 *
 * Compatibility-mode devices (#1512 Part A): the `featureLevel: 'compatibility'`
 * rung of the adapter ladder, for GL ES / older GPUs. The boot probe marks the
 * device here, so texture allocation anywhere can apply the compat rules
 * without threading a flag through every call:
 *
 *   - a texture's binding view dimension is fixed at creation
 *     (`textureBindingViewDimension`); a 2d-array with one layer (the history
 *     ring's last OOM rung, a one-layer compositor stack) must say '2d-array'
 *   - a bind group must bind every array layer (the renderer always does)
 *
 * See docs/DEVICE_FEATURES.md "Compatibility rung" for what else degrades.
 */

const compatDevices = new WeakSet<GPUDevice>();

export function markCompatDevice(device: GPUDevice): void {
  compatDevices.add(device);
}

export function isCompatDevice(device: GPUDevice | null | undefined): boolean {
  return !!device && compatDevices.has(device);
}

/** Descriptor fields for a texture bound as a 2d-array (empty on core devices). */
export function arrayBindingDescriptor(device: GPUDevice): Partial<GPUTextureDescriptor> {
  return isCompatDevice(device) ? { textureBindingViewDimension: '2d-array' } : {};
}
