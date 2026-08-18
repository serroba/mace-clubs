#!/usr/bin/env node
// Shared FIT decoding and Garmin-export helpers for the local tooling.

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { basename, join } from "node:path";
import { inflateRawSync } from "node:zlib";

import { Decoder, Stream } from "@garmin/fitsdk";

export function readFit(buffer) {
    const decoder = new Decoder(Stream.fromBuffer(buffer));
    const fieldNames = new Map();
    const { messages, errors } = decoder.read({
        fieldDescriptionListener: (key, _developerDataIdMesg, fieldDescriptionMesg) =>
            fieldNames.set(key, fieldDescriptionMesg.fieldName),
    });
    return { messages, fieldNames, errors };
}

const camelCache = new Map();

function camel(name) {
    let cached = camelCache.get(name);
    if (cached === undefined) {
        cached = name.replace(/_([a-z])/g, (_, letter) => letter.toUpperCase());
        camelCache.set(name, cached);
    }
    return cached;
}

export function messagesOf(fit, kind) {
    return fit.messages[`${camel(kind)}Mesgs`] ?? [];
}

// Native fields live on the message under the profile's camelCase name;
// developer fields sit in developerFields keyed by the decoder's sequential
// field-description key, which readFit maps back to the recorded field name.
export function fieldValue(fit, mesg, name, fallback = null) {
    const native = mesg[camel(name)];
    if (native !== undefined && native !== null) {
        return native;
    }
    const developer = mesg.developerFields;
    if (developer) {
        for (const [key, value] of Object.entries(developer)) {
            if (fit.fieldNames.get(Number(key)) === name && value !== undefined && value !== null) {
                return value;
            }
        }
    }
    return fallback;
}

export function timestampSeconds(value) {
    return value instanceof Date ? value.getTime() / 1000 : null;
}

// Python-compatible round: ties go to the nearest even integer at the target
// precision, matching the numbers the retired Python tooling produced.
export function pythonRound(value, digits = 0) {
    const factor = 10 ** digits;
    const scaled = value * factor;
    const floor = Math.floor(scaled);
    const difference = scaled - floor;
    let rounded;
    if (difference > 0.5) {
        rounded = floor + 1;
    } else if (difference < 0.5) {
        rounded = floor;
    } else {
        rounded = floor % 2 === 0 ? floor : floor + 1;
    }
    return rounded / factor;
}

const ZIP_EOCD = 0x06054b50;
const ZIP_CENTRAL = 0x02014b50;

// Garmin ZIP exports only use stored and deflate entries, so a minimal
// read-only central-directory walk avoids an archive dependency.
export function zipEntries(buffer) {
    let eocd = -1;
    for (let index = buffer.length - 22; index >= Math.max(0, buffer.length - 65557); index--) {
        if (buffer.readUInt32LE(index) === ZIP_EOCD) {
            eocd = index;
            break;
        }
    }
    if (eocd < 0) {
        throw new Error("not a ZIP archive");
    }
    const count = buffer.readUInt16LE(eocd + 10);
    let offset = buffer.readUInt32LE(eocd + 16);
    const entries = [];
    for (let index = 0; index < count; index++) {
        if (buffer.readUInt32LE(offset) !== ZIP_CENTRAL) {
            throw new Error("corrupt ZIP central directory");
        }
        const method = buffer.readUInt16LE(offset + 10);
        const compressedSize = buffer.readUInt32LE(offset + 20);
        const nameLength = buffer.readUInt16LE(offset + 28);
        const extraLength = buffer.readUInt16LE(offset + 30);
        const commentLength = buffer.readUInt16LE(offset + 32);
        const localOffset = buffer.readUInt32LE(offset + 42);
        const name = buffer.toString("utf8", offset + 46, offset + 46 + nameLength);
        entries.push({
            name,
            isDirectory: name.endsWith("/"),
            extract() {
                const localName = buffer.readUInt16LE(localOffset + 26);
                const localExtra = buffer.readUInt16LE(localOffset + 28);
                const start = localOffset + 30 + localName + localExtra;
                const data = buffer.subarray(start, start + compressedSize);
                if (method === 0) {
                    return Buffer.from(data);
                }
                if (method === 8) {
                    return inflateRawSync(data);
                }
                throw new Error(`unsupported ZIP compression method ${method} for ${name}`);
            },
        });
        offset += 46 + nameLength + extraLength + commentLength;
    }
    return entries;
}

// Resolve a raw FIT file or safely extract the activity from a ZIP.
export function fitPath(source, directory) {
    if (!source.toLowerCase().endsWith(".zip")) {
        return source;
    }
    const candidates = zipEntries(readFileSync(source)).filter(
        (entry) => !entry.isDirectory && entry.name.toLowerCase().endsWith(".fit"),
    );
    if (candidates.length === 0) {
        throw new Error(`${source} contains no FIT activity`);
    }
    if (candidates.length > 1) {
        candidates.sort((a, b) => {
            const aRank = a.name.toLowerCase().includes("activity") ? 0 : 1;
            const bRank = b.name.toLowerCase().includes("activity") ? 0 : 1;
            return aRank - bRank || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
        });
    }
    mkdirSync(directory, { recursive: true });
    const destination = join(directory, basename(candidates[0].name));
    writeFileSync(destination, candidates[0].extract());
    return destination;
}
