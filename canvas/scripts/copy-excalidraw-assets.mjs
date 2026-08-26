import { cp, mkdir, rm } from "node:fs/promises";
import { resolve } from "node:path";

const source = resolve("node_modules/@excalidraw/excalidraw/dist/excalidraw-assets");
const target = resolve(process.argv[2] ?? "dist", "excalidraw-assets");

await rm(target, { recursive: true, force: true });
await mkdir(target, { recursive: true });
await cp(source, target, { recursive: true });
