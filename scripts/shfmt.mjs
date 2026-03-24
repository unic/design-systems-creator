#!/usr/bin/env node
/**
 * CLI wrapper for @wasm-fmt/shfmt
 * Usage:
 *   node scripts/shfmt.mjs -w file1.sh file2.sh   # format in-place
 *   node scripts/shfmt.mjs -d file1.sh file2.sh   # check (exit 1 if unformatted)
 */

import { format } from "@wasm-fmt/shfmt";
import { readFileSync, writeFileSync } from "node:fs";

const args = process.argv.slice(2);
const mode = args[0];
const files = args.slice(1);

if (!files.length || (mode !== "-w" && mode !== "-d")) {
	console.error("Usage: shfmt.mjs [-w|-d] <files...>");
	process.exit(2);
}

// indent: 0 = tabs (matches .editorconfig indent_style = tab)
const options = { indent: 0 };

let dirty = false;

for (const file of files) {
	const original = readFileSync(file, "utf8");
	const formatted = format(original, file, options);

	if (original === formatted) continue;

	if (mode === "-w") {
		writeFileSync(file, formatted, "utf8");
		console.log(file);
	} else {
		console.error(`${file}: not formatted (run pnpm format to fix)`);
		dirty = true;
	}
}

if (dirty) process.exit(1);
