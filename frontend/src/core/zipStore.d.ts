export type StoreZipEntry = {
  name: string;
  data: Uint8Array | string;
  modified?: Date | string | number;
};

export function crc32(bytes: Uint8Array): number;
export function createStoreZip(entries: StoreZipEntry[]): Uint8Array;
