const encoder = new TextEncoder();

function crc32Table() {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    table[n] = c >>> 0;
  }
  return table;
}

const CRC_TABLE = crc32Table();

export function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) crc = CRC_TABLE[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function u16(value) {
  return Uint8Array.of(value & 0xff, (value >>> 8) & 0xff);
}

function u32(value) {
  return Uint8Array.of(value & 0xff, (value >>> 8) & 0xff, (value >>> 16) & 0xff, (value >>> 24) & 0xff);
}

function concat(parts) {
  const total = parts.reduce((sum, part) => sum + part.byteLength, 0);
  const output = new Uint8Array(total);
  let offset = 0;
  for (const part of parts) {
    output.set(part, offset);
    offset += part.byteLength;
  }
  return output;
}

function normalizeName(value) {
  const name = String(value || '').normalize('NFKC').replace(/\\/g, '/').replace(/^\/+/, '');
  const parts = name.split('/').filter(Boolean);
  if (!parts.length || parts.some(part => part === '.' || part === '..' || /[\u0000-\u001f]/.test(part))) throw new Error('Nome de entrada ZIP inválido.');
  return parts.join('/');
}

function dosDateTime(dateValue) {
  const date = dateValue instanceof Date ? dateValue : new Date(dateValue || Date.now());
  const safe = Number.isNaN(date.getTime()) ? new Date() : date;
  const year = Math.min(2107, Math.max(1980, safe.getFullYear()));
  const time = ((safe.getHours() & 0x1f) << 11) | ((safe.getMinutes() & 0x3f) << 5) | ((Math.floor(safe.getSeconds() / 2)) & 0x1f);
  const day = ((year - 1980) << 9) | (((safe.getMonth() + 1) & 0x0f) << 5) | (safe.getDate() & 0x1f);
  return { time, day };
}

export function createStoreZip(entries) {
  if (!Array.isArray(entries) || entries.length === 0) throw new Error('ZIP precisa de ao menos uma entrada.');
  if (entries.length > 4096) throw new Error('ZIP excede o limite de entradas.');
  const locals = [];
  const centrals = [];
  let localOffset = 0;

  for (const raw of entries) {
    const name = normalizeName(raw?.name);
    const nameBytes = encoder.encode(name);
    const data = raw?.data instanceof Uint8Array ? raw.data : encoder.encode(String(raw?.data ?? ''));
    if (data.byteLength > 0xffffffff) throw new Error(`Entrada ZIP grande demais: ${name}.`);
    const checksum = crc32(data);
    const stamp = dosDateTime(raw?.modified);
    const localHeader = concat([
      u32(0x04034b50), u16(20), u16(0x0800), u16(0), u16(stamp.time), u16(stamp.day),
      u32(checksum), u32(data.byteLength), u32(data.byteLength), u16(nameBytes.byteLength), u16(0), nameBytes,
    ]);
    locals.push(localHeader, data);
    centrals.push(concat([
      u32(0x02014b50), u16(20), u16(20), u16(0x0800), u16(0), u16(stamp.time), u16(stamp.day),
      u32(checksum), u32(data.byteLength), u32(data.byteLength), u16(nameBytes.byteLength), u16(0), u16(0),
      u16(0), u16(0), u32(0), u32(localOffset), nameBytes,
    ]));
    localOffset += localHeader.byteLength + data.byteLength;
  }

  const centralDirectory = concat(centrals);
  const body = concat(locals);
  const end = concat([
    u32(0x06054b50), u16(0), u16(0), u16(entries.length), u16(entries.length),
    u32(centralDirectory.byteLength), u32(body.byteLength), u16(0),
  ]);
  return concat([body, centralDirectory, end]);
}
