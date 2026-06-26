#!/usr/bin/env node
import { readFileSync } from "node:fs";
import process from "node:process";

const minIndex = process.argv.indexOf("--min-align");
const minAlign = BigInt(minIndex === -1 ? 16384 : process.argv[minIndex + 1]);
const file = process.argv.at(-1);
if (!file || file === "--min-align") {
  throw new Error("Usage: check-elf-load-alignment.mjs [--min-align 16384] <lib.so>");
}

const data = readFileSync(file);
if (data[0] !== 0x7f || data[1] !== 0x45 || data[2] !== 0x4c || data[3] !== 0x46) {
  throw new Error(`Not an ELF file: ${file}`);
}

const is64 = data[4] === 2;
const little = data[5] === 1;
const u16 = (offset) => little ? data.readUInt16LE(offset) : data.readUInt16BE(offset);
const u32 = (offset) => little ? data.readUInt32LE(offset) : data.readUInt32BE(offset);
const u64 = (offset) => little ? data.readBigUInt64LE(offset) : data.readBigUInt64BE(offset);
const word = (offset) => is64 ? u64(offset) : BigInt(u32(offset));

const phoff = Number(is64 ? u64(32) : BigInt(u32(28)));
const phentsize = u16(is64 ? 54 : 42);
const phnum = u16(is64 ? 56 : 44);
const loadAlignments = [];

for (let index = 0; index < phnum; index += 1) {
  const base = phoff + index * phentsize;
  if (u32(base) === 1) {
    loadAlignments.push(word(base + (is64 ? 48 : 28)));
  }
}

let ok = true;
for (const align of loadAlignments) {
  if (align < minAlign) {
    ok = false;
  }
}

console.log(loadAlignments.map((align) => `0x${align.toString(16)}`).join(","));
process.exit(ok ? 0 : 1);
