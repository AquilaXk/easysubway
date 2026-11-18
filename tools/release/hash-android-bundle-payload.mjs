#!/usr/bin/env node

import { createHash } from "node:crypto";
import { closeSync, fstatSync, lstatSync, openSync, readSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { crc32, inflateRawSync } from "node:zlib";

export const DEFAULT_MAX_ARCHIVE_BYTES = 512 * 1024 * 1024;
export const DEFAULT_MAX_ENTRIES = 65_535;
export const DEFAULT_MAX_ENTRY_BYTES = 256 * 1024 * 1024;
export const DEFAULT_MAX_TOTAL_BYTES = 512 * 1024 * 1024;

const SIGNATURE_ENTRY = /^META-INF\/(?:MANIFEST\.MF|[^/]+\.(?:SF|RSA|DSA|EC))$/i;
const EOCD_SIGNATURE = 0x06054b50;
const CENTRAL_SIGNATURE = 0x02014b50;
const LOCAL_SIGNATURE = 0x04034b50;
const ZIP64_COUNT_SENTINEL = 0xffff;
const ZIP64_SIZE_SENTINEL = 0xffffffff;
const ALLOWED_FLAGS_MASK = 0x080e;
const utf8Decoder = new TextDecoder("utf-8", { fatal: true });

function normalizeOptions(options = {}) {
  const resolved = {
    maxArchiveBytes: options.maxArchiveBytes ?? DEFAULT_MAX_ARCHIVE_BYTES,
    maxEntries: options.maxEntries ?? DEFAULT_MAX_ENTRIES,
    maxEntryBytes: options.maxEntryBytes ?? DEFAULT_MAX_ENTRY_BYTES,
    maxTotalBytes: options.maxTotalBytes ?? DEFAULT_MAX_TOTAL_BYTES,
  };
  for (const [key, value] of Object.entries(resolved)) {
    if (!Number.isSafeInteger(value) || value <= 0) {
      throw new Error(`${key} must be a positive safe integer`);
    }
  }
  return resolved;
}

function assertSafeEntryName(name, isDirectory) {
  if (name.length === 0 || name.includes("\0") || name.includes("\\") || name.startsWith("/")) {
    throw new Error(`unsafe ZIP entry name: ${JSON.stringify(name)}`);
  }
  if (/^[A-Za-z]:/.test(name)) {
    throw new Error(`unsafe ZIP entry drive path: ${name}`);
  }
  const trimmed = isDirectory ? name.slice(0, -1) : name;
  const segments = trimmed.split("/");
  if (segments.some((segment) => segment.length === 0 || segment === "." || segment === "..")) {
    throw new Error(`unsafe ZIP entry path segment: ${name}`);
  }
}

function findEocdOffset(tailBytes, archiveSize) {
  const tailStart = archiveSize - tailBytes.length;
  for (let offset = tailBytes.length - 22; offset >= 0; offset -= 1) {
    if (tailBytes.readUInt32LE(offset) !== EOCD_SIGNATURE) {
      continue;
    }
    const commentLength = tailBytes.readUInt16LE(offset + 20);
    if (tailStart + offset + 22 + commentLength === archiveSize) {
      return offset;
    }
  }
  return -1;
}

function parseCentralDirectory(reader, archiveSize, limits) {
  if (archiveSize < 22 || archiveSize > limits.maxArchiveBytes) {
    throw new Error(`Android App Bundle size (${archiveSize}) exceeds allowed archive bounds`);
  }

  const tailLength = Math.min(archiveSize, 65_557);
  const tailOffset = archiveSize - tailLength;
  const tailBytes = reader.readRange(tailOffset, tailLength);
  const eocdLocalOffset = findEocdOffset(tailBytes, archiveSize);
  if (eocdLocalOffset < 0) {
    throw new Error("Android App Bundle is missing a valid ZIP end-of-central-directory record");
  }

  const diskNumber = tailBytes.readUInt16LE(eocdLocalOffset + 4);
  const centralDisk = tailBytes.readUInt16LE(eocdLocalOffset + 6);
  const diskEntries = tailBytes.readUInt16LE(eocdLocalOffset + 8);
  const totalEntries = tailBytes.readUInt16LE(eocdLocalOffset + 10);
  const centralSize = tailBytes.readUInt32LE(eocdLocalOffset + 12);
  const centralOffset = tailBytes.readUInt32LE(eocdLocalOffset + 16);
  const eocdFileOffset = tailOffset + eocdLocalOffset;

  if (diskNumber !== 0 || centralDisk !== 0 || diskEntries !== totalEntries) {
    throw new Error("multi-disk ZIP archives are unsupported");
  }
  if (
    totalEntries === ZIP64_COUNT_SENTINEL
    || centralSize === ZIP64_SIZE_SENTINEL
    || centralOffset === ZIP64_SIZE_SENTINEL
  ) {
    throw new Error("ZIP64 Android App Bundles are unsupported");
  }
  if (totalEntries > limits.maxEntries) {
    throw new Error(`Android App Bundle entry count (${totalEntries}) exceeds limit (${limits.maxEntries})`);
  }
  if (centralOffset + centralSize !== eocdFileOffset) {
    throw new Error("Android App Bundle central directory offset mismatch");
  }

  const centralBytes = reader.readRange(centralOffset, centralSize);
  const seenNames = new Set();
  const payloadEntries = [];
  let cursor = 0;
  let plannedTotalBytes = 0;

  for (let index = 0; index < totalEntries; index += 1) {
    if (cursor + 46 > centralBytes.length || centralBytes.readUInt32LE(cursor) !== CENTRAL_SIGNATURE) {
      throw new Error("malformed ZIP central directory entry");
    }

    const flags = centralBytes.readUInt16LE(cursor + 8);
    const method = centralBytes.readUInt16LE(cursor + 10);
    const crc = centralBytes.readUInt32LE(cursor + 16);
    const compressedSize = centralBytes.readUInt32LE(cursor + 20);
    const uncompressedSize = centralBytes.readUInt32LE(cursor + 24);
    const nameLength = centralBytes.readUInt16LE(cursor + 28);
    const extraLength = centralBytes.readUInt16LE(cursor + 30);
    const commentLength = centralBytes.readUInt16LE(cursor + 32);
    const diskStart = centralBytes.readUInt16LE(cursor + 34);
    const externalAttributes = centralBytes.readUInt32LE(cursor + 38);
    const localOffset = centralBytes.readUInt32LE(cursor + 42);

    const recordEnd = cursor + 46 + nameLength + extraLength + commentLength;
    if (recordEnd > centralBytes.length) {
      throw new Error("truncated ZIP central directory record");
    }

    if ((flags & 0x0001) !== 0) {
      throw new Error("encrypted ZIP entries are unsupported");
    }
    if ((flags & ~ALLOWED_FLAGS_MASK) !== 0 || (method !== 0 && method !== 8)) {
      throw new Error(`unsupported ZIP flags (0x${flags.toString(16)}) or method (${method})`);
    }
    if (method === 0 && (flags & 0x0006) !== 0) {
      throw new Error("invalid DEFLATE flags on STORED ZIP entry");
    }
    if (
      diskStart !== 0
      || compressedSize === ZIP64_SIZE_SENTINEL
      || uncompressedSize === ZIP64_SIZE_SENTINEL
      || localOffset === ZIP64_SIZE_SENTINEL
    ) {
      throw new Error("ZIP64 or multi-disk entry attributes are unsupported");
    }
    // 상위 4비트(POSIX S_IFMT)가 0xa(0o120000)이면 심볼릭 링크 엔트리이므로 즉시 거부한다.
    if ((externalAttributes >>> 28) === 0xa) {
      throw new Error("symlink ZIP entries are forbidden");
    }

    const nameBytes = Buffer.from(centralBytes.subarray(cursor + 46, cursor + 46 + nameLength));
    const name = utf8Decoder.decode(nameBytes);
    const isDirectory = name.endsWith("/");
    assertSafeEntryName(name, isDirectory);

    if (seenNames.has(name)) {
      throw new Error(`duplicate ZIP entry name: ${name}`);
    }
    seenNames.add(name);

    if (compressedSize > limits.maxArchiveBytes || localOffset + 30 > centralOffset) {
      throw new Error(`ZIP entry bounds exceed archive range: ${name}`);
    }

    if (!isDirectory) {
      if ((externalAttributes >>> 28) === 0x4) {
        throw new Error(`malformed directory mode on non-directory ZIP entry: ${name}`);
      }
      if (method === 0 && compressedSize !== uncompressedSize) {
        throw new Error(`STORED ZIP entry size mismatch: ${name}`);
      }
      if (uncompressedSize > limits.maxEntryBytes) {
        throw new Error(`ZIP entry exceeds uncompressed size limit (${limits.maxEntryBytes}): ${name}`);
      }
      if (!SIGNATURE_ENTRY.test(name)) {
        plannedTotalBytes += uncompressedSize;
        if (plannedTotalBytes > limits.maxTotalBytes) {
          throw new Error(`ZIP payload exceeds total uncompressed size limit (${limits.maxTotalBytes})`);
        }
        payloadEntries.push({
          name,
          nameBytes,
          flags,
          method,
          crc,
          compressedSize,
          uncompressedSize,
          localOffset,
        });
      }
    }

    cursor = recordEnd;
  }

  if (cursor !== centralBytes.length) {
    throw new Error("trailing bytes detected in ZIP central directory");
  }
  if (payloadEntries.length === 0) {
    throw new Error("Android App Bundle contains no payload entries");
  }

  return { centralOffset, payloadEntries };
}

function readEntryPayload(reader, entry, centralOffset, maxInflateBytes) {
  const localHeader = reader.readRange(entry.localOffset, 30);
  if (localHeader.readUInt32LE(0) !== LOCAL_SIGNATURE) {
    throw new Error(`invalid ZIP local file header: ${entry.name}`);
  }
  const localFlags = localHeader.readUInt16LE(6);
  const localMethod = localHeader.readUInt16LE(8);
  const localCrc = localHeader.readUInt32LE(14);
  const localCompressed = localHeader.readUInt32LE(18);
  const localUncompressed = localHeader.readUInt32LE(22);
  const localNameLength = localHeader.readUInt16LE(26);
  const localExtraLength = localHeader.readUInt16LE(28);

  if (localFlags !== entry.flags || localMethod !== entry.method) {
    throw new Error(`ZIP local header mismatch: ${entry.name}`);
  }
  const usesDataDescriptor = (entry.flags & 0x0008) !== 0;
  if (usesDataDescriptor) {
    const zeroed = localCrc === 0 && localCompressed === 0 && localUncompressed === 0;
    const matched = localCrc === entry.crc
      && localCompressed === entry.compressedSize
      && localUncompressed === entry.uncompressedSize;
    if (!zeroed && !matched) {
      throw new Error(`ZIP local data descriptor header mismatch: ${entry.name}`);
    }
  } else if (
    localCrc !== entry.crc
    || localCompressed !== entry.compressedSize
    || localUncompressed !== entry.uncompressedSize
  ) {
    throw new Error(`ZIP local size/CRC header mismatch: ${entry.name}`);
  }

  const nameOffset = entry.localOffset + 30;
  const dataOffset = nameOffset + localNameLength + localExtraLength;
  if (dataOffset + entry.compressedSize > centralOffset) {
    throw new Error(`ZIP entry data extends beyond central directory: ${entry.name}`);
  }

  const localName = reader.readRange(nameOffset, localNameLength);
  if (!localName.equals(entry.nameBytes)) {
    throw new Error(`ZIP local entry name mismatch: ${entry.name}`);
  }

  const compressedData = reader.readRange(dataOffset, entry.compressedSize);
  const contents = entry.method === 0
    ? compressedData
    : inflateRawSync(compressedData, { maxOutputLength: maxInflateBytes });

  if (contents.length !== entry.uncompressedSize) {
    throw new Error(`ZIP entry decompressed size mismatch: ${entry.name}`);
  }
  if (crc32(contents) !== entry.crc) {
    throw new Error(`ZIP entry CRC-32 mismatch: ${entry.name}`);
  }
  return contents;
}

function computePayloadHash(reader, archiveSize, options) {
  const limits = normalizeOptions(options);
  const { centralOffset, payloadEntries } = parseCentralDirectory(reader, archiveSize, limits);

  payloadEntries.sort((left, right) => (left.name < right.name ? -1 : left.name > right.name ? 1 : 0));

  const digest = createHash("sha256");
  const lengths = Buffer.allocUnsafe(12);
  let totalDecodedBytes = 0;

  for (const entry of payloadEntries) {
    const remainingBudget = limits.maxTotalBytes - totalDecodedBytes;
    const maxInflateBytes = Math.min(limits.maxEntryBytes, remainingBudget);
    if (entry.uncompressedSize > maxInflateBytes) {
      throw new Error(`ZIP payload exceeds total uncompressed size limit (${limits.maxTotalBytes})`);
    }
    const contents = readEntryPayload(reader, entry, centralOffset, maxInflateBytes);
    totalDecodedBytes += contents.length;
    if (totalDecodedBytes > limits.maxTotalBytes) {
      throw new Error(`ZIP payload exceeds total uncompressed size limit (${limits.maxTotalBytes})`);
    }

    lengths.writeUInt32BE(entry.nameBytes.length, 0);
    lengths.writeBigUInt64BE(BigInt(contents.length), 4);
    digest.update(lengths);
    digest.update(entry.nameBytes);
    digest.update(contents);
  }

  return digest.digest("hex");
}

export function hashAndroidBundlePayloadBuffer(bytes, options = {}) {
  if (!Buffer.isBuffer(bytes)) {
    throw new Error("Android App Bundle buffer must be a Buffer");
  }
  return computePayloadHash(
    {
      readRange(offset, length) {
        if (offset < 0 || length < 0 || offset + length > bytes.length) {
          throw new Error("ZIP read out of bounds");
        }
        return bytes.subarray(offset, offset + length);
      },
    },
    bytes.length,
    options,
  );
}

export function hashAndroidBundlePayload(aabPath, options = {}) {
  if (typeof aabPath !== "string" || aabPath.length === 0) {
    throw new Error("--aab must reference an existing Android App Bundle");
  }
  let stat;
  try {
    stat = lstatSync(aabPath);
  } catch {
    throw new Error("--aab must reference an existing Android App Bundle");
  }
  if (!stat.isFile()) {
    throw new Error("--aab must reference a regular file");
  }

  const fd = openSync(aabPath, "r");
  try {
    const fileSize = fstatSync(fd).size;
    return computePayloadHash(
      {
        readRange(offset, length) {
          if (offset < 0 || length < 0 || offset + length > fileSize) {
            throw new Error("ZIP read out of bounds");
          }
          const buffer = Buffer.allocUnsafe(length);
          let bytesRead = 0;
          while (bytesRead < length) {
            const readNow = readSync(fd, buffer, bytesRead, length - bytesRead, offset + bytesRead);
            if (readNow <= 0) {
              throw new Error("unexpected EOF while reading Android App Bundle");
            }
            bytesRead += readNow;
          }
          return buffer;
        },
      },
      fileSize,
      options,
    );
  } finally {
    closeSync(fd);
  }
}

function parseCliArgs(argv) {
  const options = {};
  let aabPath = null;
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (value === undefined) {
      throw new Error(`missing value for argument: ${flag}`);
    }
    switch (flag) {
      case "--aab":
        aabPath = value;
        break;
      case "--max-entry-bytes":
        options.maxEntryBytes = parsePositiveIntFlag(flag, value);
        break;
      case "--max-total-bytes":
        options.maxTotalBytes = parsePositiveIntFlag(flag, value);
        break;
      case "--max-archive-bytes":
        options.maxArchiveBytes = parsePositiveIntFlag(flag, value);
        break;
      case "--max-entries":
        options.maxEntries = parsePositiveIntFlag(flag, value);
        break;
      default:
        throw new Error(`unknown argument: ${flag}`);
    }
  }
  if (!aabPath) {
    throw new Error("--aab must reference an existing Android App Bundle");
  }
  return { aabPath, options };
}

function parsePositiveIntFlag(flag, raw) {
  if (!/^[1-9]\d*$/.test(raw)) {
    throw new Error(`${flag} must be a positive integer`);
  }
  const parsed = Number(raw);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    throw new Error(`${flag} must be a positive safe integer`);
  }
  return parsed;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const { aabPath, options } = parseCliArgs(process.argv.slice(2));
  process.stdout.write(`${hashAndroidBundlePayload(aabPath, options)}\n`);
}
