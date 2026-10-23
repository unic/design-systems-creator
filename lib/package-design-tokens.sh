#!/usr/bin/env bash

# =============================================================================
# Design Tokens Package Module
# =============================================================================
# Functions for creating the @repo/design-tokens package with a modular
# Tokens Studio + Style Dictionary build pipeline (split → per-brand build).

create_design_tokens_package() {
	log_info "Creating @repo/design-tokens package..."
	cd "$TARGET_FOLDER/packages" || exit

	mkdir -p design-tokens
	cd design-tokens || exit

	pnpm init --bare

	jq \
		--arg name "@repo/design-tokens" \
		--arg description "Design tokens for the ${ORGANIZATION_NAME} Design System (Style Dictionary + DTCG)" \
		--arg author "${DEVELOPER}" \
		'. + {
			name: $name,
			version: "1.0.0",
			description: $description,
			author: $author,
			license: "LGPL-3.0-or-later",
			type: "module",
			private: true,
			exports: {
				"./css": "./dist/tokens.css",
				"./tailwind-theme": "./dist/tailwind-theme.css",
				"./*": "./dist/*"
			},
			files: ["dist"],
			scripts: {
				"build": "node ./scripts/build-style-dictionary.mjs",
				"build:watch": "chokidar \"tokens/**/*.json\" \"token-config.js\" \"lib/**/*.mjs\" \"scripts/**/*.mjs\" -c \"pnpm build\"",
				"split-tokens": "node ./scripts/split-design-tokens.mjs",
				"clean": "rm -rf dist temp",
				"typecheck": "tsc --noEmit"
			},
			devDependencies: {
				"@repo/typescript-config": "workspace:*",
				"@tokens-studio/sd-transforms": "catalog:",
				"chokidar-cli": "catalog:",
				"style-dictionary": "catalog:",
				"typescript": "catalog:"
			}
		}' package.json >package.json.tmp && mv package.json.tmp package.json

	log_success "@repo/design-tokens package created"
}

add_design_tokens_config() {
	log_info "Adding design tokens build pipeline (lib/, scripts/, token-config.js)..."
	cd "$TARGET_FOLDER/packages/design-tokens" || exit

	mkdir -p lib scripts

	cat >lib/registerTransforms.mjs <<'EOF'
/**
 * @fileoverview
 * Registers the `tokens-studio` preprocessor + transform group on Style
 * Dictionary, plus our custom Tailwind v4 `@theme` CSS format.
 *
 * `excludeParentKeys` stays off: the splitter already removes each set-name
 * wrapper, so the preprocessor must not strip another level.
 *
 * Must be called once before constructing any `StyleDictionary` instance.
 */

import StyleDictionary from 'style-dictionary'
import { register as registerTokensStudio } from '@tokens-studio/sd-transforms'

/** @returns {void} */
function registerTransforms() {
	registerTokensStudio(StyleDictionary)

	// Tokens Studio applies a unitless line height or letter spacing as pixels;
	// in CSS a bare line height is a multiplier and a bare letter spacing is
	// invalid. Runs before `expand`, so it also fixes typography properties.
	const UNITLESS_PX_TYPES = new Set(['lineHeights', 'lineHeight', 'letterSpacing'])
	const toPx = (value) => (/^-?(\d+\.?\d*|\.\d+)$/.test(String(value).trim()) && Number(value) !== 0 ? `${String(value).trim()}px` : value)
	StyleDictionary.registerPreprocessor({
		name: 'unitless-px',
		preprocessor: (dictionary) => {
			const walk = (node) => {
				if (!node || typeof node !== 'object') return
				const key = '$value' in node ? '$value' : 'value' in node ? 'value' : null
				if (!key) return Object.values(node).forEach(walk)
				const type = node.$type ?? node.type
				if (UNITLESS_PX_TYPES.has(type)) node[key] = toPx(node[key])
				if (type === 'typography' && node[key] && typeof node[key] === 'object') {
					for (const property of ['lineHeight', 'letterSpacing']) {
						if (property in node[key]) node[key][property] = toPx(node[key][property])
					}
				}
			}
			walk(dictionary)
			return dictionary
		},
	})

	// Tokens Studio exports Figma "Auto" line height as `AUTO`, which is invalid CSS.
	StyleDictionary.registerTransform({
		name: 'value/line-height-auto',
		type: 'value',
		transitive: true,
		filter: (token) => (token.$type ?? token.type) === 'lineHeight' && String(token.$value ?? token.value).toUpperCase() === 'AUTO',
		transform: () => 'normal',
	})

	// CSS platforms run this after the `tokens-studio` group. Typography and
	// composition are expanded before; the group turns shadow and border
	// composites into strings. Anything still an object fails here.
	StyleDictionary.registerTransform({
		name: 'value/css-serializable',
		type: 'value',
		// Composites almost always hold references; run on those too.
		transitive: true,
		filter: (token) => typeof (token.$value ?? token.value) === 'object',
		transform: (token) => {
			const value = token.$value ?? token.value
			if (Array.isArray(value)) return value.join(', ')
			throw new Error(`Token "${token.path.join('.')}" has no CSS-serializable value. Composite types such as composition are not supported.`)
		},
	})

	StyleDictionary.registerFormat({
		name: 'tailwind/theme-css',
		/** @param {{ dictionary: any, file: any }} args */
		format: ({ dictionary, file }) => {
			const lines = [
				'/**',
				` * ${file?.destination ?? 'tailwind-theme.css'}`,
				' * Tailwind v4 @theme block — auto-generated from design tokens.',
				' * Do not edit directly. Regenerated by @repo/design-tokens build.',
				' */',
				'',
				'@theme {',
			]

			for (const token of dictionary.allTokens) {
				const cssVarName = `--${token.name}`
				const value = token.$value ?? token.value
				lines.push(`\t${cssVarName}: ${value};`)
			}

			lines.push('}', '')
			return lines.join('\n')
		},
	})
}

export default registerTransforms
EOF

	cat >lib/platformConfigs.mjs <<'EOF'
/**
 * @fileoverview
 * Platform configuration factories for Style Dictionary.
 *
 * Trimmed for our Tailwind-v4-first setup. Each factory returns a fully-formed
 * platform config to plug into Style Dictionary. To add platforms (iOS, Android,
 * SCSS, etc.), add a factory here and register its key in `PLATFORM_FACTORIES`
 * — see https://github.com/orioltf/poc-tokens for examples.
 */

import { outputReferencesFilter, outputReferencesTransformed } from 'style-dictionary/utils'

/** @param {any} token */
const isPureAlias = (token) => /^\{[^{}]+\}$/.test(String(token.original.$value ?? token.original.value).trim())

/**
 * Tailwind v4 `@theme` block CSS. This is the primary runtime contract.
 * Consumers `@import "@repo/design-tokens/tailwind-theme"` from their app
 * stylesheet.
 *
 * @param {string} buildPath - Absolute output directory (already brand-scoped).
 * @returns {object}
 */
export function createTailwindCssPlatform(buildPath) {
	return {
		buildPath: buildPath.endsWith('/') ? buildPath : `${buildPath}/`,
		transformGroup: 'tokens-studio',
		transforms: ['name/kebab', 'value/line-height-auto', 'value/css-serializable'],
		files: [
			{
				destination: 'tailwind-theme.css',
				format: 'tailwind/theme-css',
			},
		],
	}
}

/**
 * Plain CSS custom properties (`:root { --token-name: value; }`) for any
 * consumer that wants raw variables without the Tailwind `@theme` wrapper.
 *
 * @param {string} buildPath
 * @returns {object}
 */
export function createCssVarsPlatform(buildPath) {
	return {
		buildPath: buildPath.endsWith('/') ? buildPath : `${buildPath}/`,
		transformGroup: 'tokens-studio',
		transforms: ['name/kebab', 'value/line-height-auto', 'value/css-serializable'],
		files: [
			{
				destination: 'tokens.css',
				format: 'css/variables',
				options: {
					// Keep `var(--ref-name)` only for a pure alias (`{a.b}`) whose target
					// is in this file's output and whose value no transform changed
					// (e.g. color modifiers). Inline everything else, such as Tokens
					// Studio math (`-{a} * 2`), which would be invalid CSS around a
					// `var()`. Missing references fail the build instead.
					// https://styledictionary.com/reference/utils/references/
					outputReferences: (token, options) =>
						isPureAlias(token) && outputReferencesFilter(token, options) && outputReferencesTransformed(token, options),
				},
			},
		],
	}
}

/**
 * ESM + CJS + d.ts JavaScript outputs for type-safe runtime consumption
 * (e.g. JS-driven theming, Storybook stories, design audits).
 *
 * @param {string} buildPath
 * @returns {object}
 */
export function createJsPlatform(buildPath) {
	return {
		buildPath: buildPath.endsWith('/') ? buildPath : `${buildPath}/`,
		transformGroup: 'tokens-studio',
		transforms: ['name/camel'],
		files: [
			{ destination: 'index.js', format: 'javascript/es6' },
			{ destination: 'index.cjs', format: 'javascript/module-flat' },
			{ destination: 'index.d.ts', format: 'typescript/es6-declarations' },
		],
	}
}

/**
 * Map of platform-key → factory. The build script picks platforms by key
 * from `token-config.js#platforms`.
 */
const PLATFORM_FACTORIES = {
	'tailwind-css': createTailwindCssPlatform,
	'css-vars': createCssVarsPlatform,
	js: createJsPlatform,
}

/**
 * Returns the configured platforms for a brand, keyed for Style Dictionary.
 *
 * @param {string} buildPath - Absolute output directory for this brand.
 * @param {string[]} platformKeys
 * @returns {Record<string, object>}
 */
export function getPlatformsForBrand(buildPath, platformKeys) {
	const platforms = {}
	for (const key of platformKeys) {
		const factory = PLATFORM_FACTORIES[key]
		if (!factory) {
			throw new Error(`Unknown platform "${key}" in token-config.js. Known: ${Object.keys(PLATFORM_FACTORIES).join(', ')}`)
		}
		platforms[key] = factory(buildPath)
	}
	return platforms
}
EOF

	cat >lib/configManager.mjs <<'EOF'
/**
 * @fileoverview
 * Configuration Manager for the design tokens build pipeline.
 *
 * Centralizes loading and exposing config for the splitter and the Style
 * Dictionary build.
 */

import { existsSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)
const PACKAGE_ROOT = path.resolve(__dirname, '..')

/**
 * @typedef {object} TokensBuildConfig
 * @property {string[]} brands
 * @property {string[]} platforms
 * @property {string[]} excludeKeys
 * @property {string[]} includeKeys
 * @property {Record<string, string[]>} brandSets
 * @property {string} sourcePathPrefix
 * @property {string} buildPathPrefix
 * @property {string} tempDir
 * @property {string[]} inputFiles - Paths to token JSON files (relative to sourcePathPrefix or absolute).
 */

/** @type {TokensBuildConfig} */
const DEFAULT_CONFIG = {
	brands: ['brandName'],
	platforms: ['tailwind-css', 'css-vars'],
	excludeKeys: [],
	includeKeys: [],
	brandSets: {},
	sourcePathPrefix: path.join(PACKAGE_ROOT, 'tokens'),
	buildPathPrefix: path.join(PACKAGE_ROOT, 'dist'),
	tempDir: path.join(PACKAGE_ROOT, 'temp'),
	inputFiles: ['primitive-design-tokens.json'],
}

class ConfigManager {
	constructor() {
		/** @type {TokensBuildConfig} */
		this.config = { ...DEFAULT_CONFIG }
	}

	/**
	 * Load and merge user config from a JS module file. Falls back to defaults
	 * only when the file is absent; load errors propagate.
	 * @param {string} [configPath] - Absolute path to a `token-config.js` module.
	 * @returns {Promise<TokensBuildConfig>}
	 */
	async loadFromFile(configPath = path.join(PACKAGE_ROOT, 'token-config.js')) {
		if (!existsSync(configPath)) {
			console.warn(`[design-tokens] No config at ${configPath}. Using defaults.`)
			return this.config
		}
		const mod = await import(pathToFileURL(configPath).href)
		if (!mod.default || typeof mod.default !== 'object') {
			throw new Error(`${configPath} must have a default export with the config object.`)
		}
		this.mergeConfig(mod.default)
		return this.config
	}

	/**
	 * Shallow-merge user config over defaults. Unknown keys throw.
	 * @param {Partial<TokensBuildConfig>} userConfig
	 * @returns {TokensBuildConfig}
	 */
	mergeConfig(userConfig) {
		const unknown = Object.keys(userConfig).filter((key) => !(key in DEFAULT_CONFIG))
		if (unknown.length > 0) {
			throw new Error(`Unknown token-config.js key(s): ${unknown.join(', ')}. Known: ${Object.keys(DEFAULT_CONFIG).join(', ')}`)
		}
		Object.assign(this.config, userConfig)
		return this.config
	}

	/** @returns {string[]} Absolute paths to all source token JSON files. */
	getInputFilePaths() {
		return this.config.inputFiles.map((f) =>
			path.isAbsolute(f) ? f : path.join(this.config.sourcePathPrefix, f)
		)
	}

	/** @returns {{inputFiles: string[], outputDir: string, includeKeys: string[], excludeKeys: string[]}} */
	getSplitConfig() {
		const { excludeKeys, includeKeys } = this.config
		if (includeKeys.length > 0 && excludeKeys.length > 0) {
			throw new Error('Cannot specify both includeKeys and excludeKeys in token-config.js. Choose one approach.')
		}
		return {
			excludeKeys,
			includeKeys,
			inputFiles: this.getInputFilePaths(),
			outputDir: this.config.tempDir,
		}
	}

	/** @returns {{brands: string[], platforms: string[], buildPathPrefix: string, tempDir: string, brandSets: Record<string,string[]>}} */
	getBrandPlatformConfig() {
		const { brands, platforms, brandSets } = this.config
		if (brands.length === 0 || platforms.length === 0) {
			throw new Error('token-config.js needs at least one brand and one platform.')
		}
		const strayBrandSets = Object.keys(brandSets).filter((brand) => !brands.includes(brand))
		const relativeTempDir = path.relative(this.config.buildPathPrefix, this.config.tempDir)
		if (!relativeTempDir.startsWith('..') && !path.isAbsolute(relativeTempDir)) {
			throw new Error('tempDir must not be inside buildPathPrefix: the build replaces buildPathPrefix.')
		}
		if (strayBrandSets.length > 0) {
			throw new Error(`brandSets key(s) not in brands: ${strayBrandSets.join(', ')}. Brands: ${brands.join(', ')}`)
		}
		return {
			brands: this.config.brands,
			platforms: this.config.platforms,
			buildPathPrefix: this.config.buildPathPrefix,
			tempDir: this.config.tempDir,
			brandSets: this.config.brandSets,
		}
	}
}

export default ConfigManager
EOF

	cat >lib/buildBrands.mjs <<'EOF'
/**
 * @fileoverview
 * Brand orchestrator. For each configured brand, instantiates one Style
 * Dictionary build covering all configured platforms and runs it.
 */

import path from 'node:path'
import { existsSync, readdirSync } from 'node:fs'

import StyleDictionary from 'style-dictionary'
import { expandTypesMap } from '@tokens-studio/sd-transforms'

import { getPlatformsForBrand } from './platformConfigs.mjs'

// sd-transforms leaves composition padding and size properties untyped, so
// they would lose their `px` unit.
const COMPOSITION_DIMENSIONS = [
	'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft', 'horizontalPadding', 'verticalPadding', 'itemSpacing',
	'width', 'height', 'minWidth', 'maxWidth', 'minHeight', 'maxHeight', 'fontSizes', 'backgroundBlur',
	'borderRadiusTopLeft', 'borderRadiusTopRight', 'borderRadiusBottomRight', 'borderRadiusBottomLeft',
	'borderWidthTop', 'borderWidthRight', 'borderWidthBottom', 'borderWidthLeft',
]
const TYPES_MAP = {
	...expandTypesMap,
	composition: {
		...expandTypesMap.composition,
		...Object.fromEntries(COMPOSITION_DIMENSIONS.map((property) => [property, 'dimension'])),
		fontWeights: 'fontWeight',
		lineHeights: 'lineHeight',
		fontFamilies: 'fontFamily',
	},
}

/**
 * @typedef {object} BuildOptions
 * @property {string} buildPathPrefix
 * @property {string} tempDir
 * @property {string[]} platforms
 * @property {Record<string, string[]>} brandSets - Optional per-brand subset
 *   of split set-file *basenames* (without `.json`). Empty/missing → use all.
 * @property {boolean} [verbose] - Verbose Style Dictionary logging.
 */

/**
 * Resolve the source files for a given brand. Honors `brandSets[brand]`;
 * falls back to all `*.json` in the temp dir.
 *
 * @param {string} brand
 * @param {BuildOptions} options
 * @returns {string[]} Absolute file paths.
 */
function resolveSourceFiles(brand, options) {
	const subset = options.brandSets?.[brand]
	const available = existsSync(options.tempDir) ? readdirSync(options.tempDir).filter((file) => file.endsWith('.json')) : []

	if (available.length === 0) {
		throw new Error(`No set files in ${options.tempDir}. Run the build without --skip-split.`)
	}

	if (!subset || subset.length === 0) {
		return available.map((file) => path.join(options.tempDir, file))
	}

	const missing = subset.filter((name) => !available.includes(`${name}.json`))
	if (missing.length > 0) {
		throw new Error(`brandSets[${brand}] lists unknown set(s): ${missing.join(', ')}. Available: ${available.map((file) => path.basename(file, '.json')).join(', ')}`)
	}
	return subset.map((name) => path.join(options.tempDir, `${name}.json`))
}

/**
 * Build all brand × platform combinations. The first brand builds to
 * `buildPathPrefix`; further brands to `buildPathPrefix/<brand>/`.
 *
 * @param {string[]} brands
 * @param {BuildOptions} options
 * @returns {Promise<void>}
 */
async function buildBrands(brands, options) {
	for (const [index, brand] of brands.entries()) {
		const sourceFiles = resolveSourceFiles(brand, options)
		console.log(`\n[${brand}] using ${sourceFiles.length} set file(s):`)
		for (const file of sourceFiles) console.log(`  - ${path.basename(file)}`)

		// The first brand is the default bundle the package `exports` point to.
		const brandBuildPath = index === 0 ? options.buildPathPrefix : path.join(options.buildPathPrefix, brand)
		const platforms = getPlatformsForBrand(brandBuildPath, options.platforms)

		// `init: false` + `await sd.init()` so errors raised while loading sources
		// (e.g. token collisions) reject here instead of as an unhandled rejection.
		const sd = new StyleDictionary(
			{
				// Style Dictionary reads `source` entries as globs: escape set names
				// and paths such as `[Brand] A`.
				source: sourceFiles.map((file) => file.split(path.sep).join('/').replace(/[*?[\]{}()!]/g, '\\$&')),
				preprocessors: ['unitless-px', 'tokens-studio'],
				// One variable per property: the CSS `font` shorthand cannot hold
				// `letterSpacing` and friends, and composition has no CSS form.
				expand: { include: ['typography', 'composition'], typesMap: TYPES_MAP },
				platforms,
				log: {
					// Token collisions and empty output files mean wrong or missing CSS.
					warnings: 'error',
					verbosity: options.verbose ? 'verbose' : 'default',
					errors: { brokenReferences: 'throw' },
				},
			},
			{ init: false },
		)

		await sd.init()
		if (Object.keys(sd.tokens ?? {}).length === 0) {
			throw new Error(`[${brand}] loaded no tokens from ${sourceFiles.length} set file(s).`)
		}
		await sd.buildAllPlatforms()
		console.log(`[${brand}] built platforms: ${Object.keys(platforms).join(', ')}`)
	}
}

export default buildBrands
EOF

	cat >scripts/split-design-tokens.mjs <<'EOF'
/**
 * @fileoverview
 * Merges one or more Tokens Studio JSON exports and splits them into per-set
 * JSON files in `tempDir`. Each top-level key (other than `$`-prefixed
 * Tokens Studio metadata and any user-excluded set) becomes one file holding
 * the set contents without the set-name wrapper. Slashes in the set name
 * become underscores (so `Theme/Brand Light` → `Theme_Brand Light.json`).
 *
 * Adapted from https://github.com/orioltf/poc-tokens — same shape, smaller
 * surface area.
 */

import { realpathSync } from 'node:fs'
import fs from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

/**
 * @typedef {object} SplitOptions
 * @property {string[]} inputFiles - Absolute paths to token JSON files to merge and split.
 * @property {string} outputDir - Absolute path to the temp output dir.
 * @property {string[]} [includeKeys] - If non-empty, only these top-level
 *   keys are split.
 * @property {string[]} [excludeKeys] - Top-level keys to skip. Mutually
 *   exclusive with `includeKeys`.
 */

/**
 * Return the token format of the first token found, or `undefined` if none.
 * @param {unknown} node
 * @returns {'dtcg' | 'legacy' | undefined}
 */
function detectFormat(node) {
	if (!node || typeof node !== 'object') return undefined
	if ('$value' in node) return 'dtcg'
	if ('value' in node && 'type' in node) return 'legacy'
	for (const [key, child] of Object.entries(node)) {
		if (key.startsWith('$')) continue
		const format = detectFormat(child)
		if (format) return format
	}
	return undefined
}

/**
 * Read and merge all source files, split by top-level keys, and write per-set files.
 *
 * @param {SplitOptions} options
 * @returns {Promise<string[]>} Absolute paths to the generated files.
 */
async function splitDesignTokens({ excludeKeys = [], includeKeys = [], inputFiles, outputDir }) {
	if (includeKeys.length > 0 && excludeKeys.length > 0) {
		throw new Error('splitDesignTokens: cannot specify both includeKeys and excludeKeys.')
	}

	console.log(`[split] outDir:  ${outputDir}`)

	// Read and merge all source files into one token map.
	const tokens = {}
	const setSource = new Map()
	const formatSource = new Map()
	for (const inputFile of inputFiles) {
		console.log(`[split] source:  ${inputFile}`)
		let raw
		try {
			raw = await fs.readFile(inputFile, 'utf8')
		} catch (error) {
			if (error.code === 'ENOENT') {
				throw new Error(`Design tokens file not found at: ${inputFile}`)
			}
			throw error
		}

		let parsed
		try {
			parsed = JSON.parse(raw)
		} catch (error) {
			throw new Error(`Invalid JSON in ${inputFile}: ${error.message}`)
		}

		if (!parsed.$metadata) {
			throw new Error(`${inputFile} has no $metadata. inputFiles must be single-file Tokens Studio exports, not set files from a multi-file sync.`)
		}
		// Style Dictionary picks DTCG or legacy once per build and drops tokens
		// in the other format.
		const format = detectFormat(parsed)
		if (format) formatSource.set(format, formatSource.get(format) ?? inputFile)
		if (formatSource.size > 1) {
			throw new Error(`${formatSource.get('dtcg')} uses DTCG $value/$type and ${formatSource.get('legacy')} uses legacy value/type. Export all inputFiles in one format.`)
		}

		for (const [key, value] of Object.entries(parsed)) {
			if (!key.startsWith('$') && setSource.has(key)) {
				throw new Error(`Set "${key}" is in both ${setSource.get(key)} and ${inputFile}. Rename one of them in Tokens Studio.`)
			}
			setSource.set(key, inputFile)
			tokens[key] = value
		}
	}

	const allKeys = Object.keys(tokens)
	let keysToProcess = allKeys.filter((key) => !key.startsWith('$'))

	if (includeKeys.length > 0) {
		const missing = includeKeys.filter((key) => !allKeys.includes(key))
		if (missing.length > 0) throw new Error(`splitDesignTokens: includeKeys not found in source: ${missing.join(', ')}`)
		keysToProcess = includeKeys
	} else if (excludeKeys.length > 0) {
		keysToProcess = keysToProcess.filter((key) => !excludeKeys.includes(key))
	}

	if (keysToProcess.length === 0) {
		throw new Error('splitDesignTokens: nothing to process after applying include/exclude filters.')
	}

	console.log(`[split] processing ${keysToProcess.length} set(s) from ${allKeys.length} top-level key(s)`)

	await fs.mkdir(outputDir, { recursive: true })
	// Wipe the temp dir so removed sets don't linger between runs.
	for (const entry of await fs.readdir(outputDir)) {
		if (entry.endsWith('.json')) await fs.rm(path.join(outputDir, entry))
	}

	const generated = []
	const setByFilename = new Map()
	for (const key of keysToProcess) {
		const setValue = tokens[key]
		if (!setValue || typeof setValue !== 'object' || Object.keys(setValue).length === 0) {
			console.warn(`[split] skipping "${key}" — empty or non-object set`)
			continue
		}
		if ('value' in setValue || '$value' in setValue) {
			throw new Error(`"${key}" is a token, not a set. inputFiles must be single-file Tokens Studio exports, not set files from a multi-file sync.`)
		}

		const filename = `${key.replace(/\//g, '_')}.json`
		if (setByFilename.has(filename)) {
			throw new Error(`splitDesignTokens: sets "${setByFilename.get(filename)}" and "${key}" both map to ${filename}. Rename one of them.`)
		}
		setByFilename.set(filename, key)
		const outputPath = path.join(outputDir, filename)
		await fs.writeFile(outputPath, JSON.stringify(setValue, null, 2))
		console.log(`[split]  wrote ${filename}`)
		generated.push(outputPath)
	}

	if (generated.length === 0) {
		throw new Error('splitDesignTokens: 0 files generated. Check your config and source data.')
	}
	return generated
}

// Standalone CLI: `pnpm split-tokens` → load token-config.js, split, exit.
// Compare filesystem paths: `import.meta.url` is URL-encoded and symlink-resolved.
if (process.argv[1] && fileURLToPath(import.meta.url) === realpathSync(process.argv[1])) {
	const { default: ConfigManager } = await import('../lib/configManager.mjs')
	const configManager = new ConfigManager()
	try {
		await configManager.loadFromFile()
		await splitDesignTokens(configManager.getSplitConfig())
		console.log('\n[split] done.')
	} catch (error) {
		console.error(`\n[split] failed: ${error.message}`)
		process.exit(1)
	}
}

export default splitDesignTokens
EOF

	cat >scripts/build-style-dictionary.mjs <<'EOF'
/**
 * @fileoverview
 * Main entry point for the design tokens build.
 *
 * Pipeline:
 *   1. Load the package's `token-config.js` (defaults apply only when the
 *      file is absent).
 *   2. Split the configured `inputFiles` into per-set files in `temp/`.
 *   3. For each configured brand, run Style Dictionary against the relevant
 *      set files for the configured platforms, into `temp/dist-staging/`.
 *   4. Replace `dist/` with the staging directory. A failed Style Dictionary
 *      build leaves the previous `dist/` in place.
 *
 * CLI flags (optional; unknown flags fail):
 *   --source=path/to/tokens.json    Replace `inputFiles[0]`; other inputs stay.
 *   --skip-split                    Reuse existing temp/ contents. Not with --source.
 *   --verbose                       Verbose Style Dictionary logging.
 */

import fs from 'node:fs/promises'
import path from 'node:path'

import buildBrands from '../lib/buildBrands.mjs'
import ConfigManager from '../lib/configManager.mjs'
import registerTransforms from '../lib/registerTransforms.mjs'
import splitDesignTokens from './split-design-tokens.mjs'

registerTransforms()

/**
 * Parse `--source=PATH`, `--skip-split` and `--verbose`. Anything else throws.
 * @param {string[]} argv
 * @returns {{ source?: string, skipSplit: boolean, verbose: boolean }}
 */
function parseArgs(argv) {
	const out = { skipSplit: false, verbose: false }
	for (const arg of argv) {
		// pnpm passes the `--` separator through (`pnpm build -- --verbose`).
		if (arg === '--') continue
		if (arg === '--skip-split') out.skipSplit = true
		else if (arg === '--verbose') out.verbose = true
		else if (arg.startsWith('--source=')) out.source = arg.slice('--source='.length)
		else throw new Error(`Unknown argument "${arg}". Use --source=PATH, --skip-split or --verbose.`)
	}
	if (out.source === '') throw new Error('--source= needs a path.')
	if (out.source !== undefined && out.skipSplit) {
		throw new Error('--source has no effect with --skip-split. Drop one of them.')
	}
	return out
}

const exec = async (argv = []) => {
	console.log('[design-tokens] build started')

	const configManager = new ConfigManager()
	let cli, splitConfig, brandPlatformConfig
	try {
		cli = parseArgs(argv)
		await configManager.loadFromFile()
		if (cli.source !== undefined) {
			// pnpm runs scripts in the package dir; INIT_CWD is where pnpm was called.
			const callerDir = process.env.INIT_CWD ?? process.cwd()
			const [, ...supplementaryFiles] = configManager.config.inputFiles
			configManager.mergeConfig({ inputFiles: [path.resolve(callerDir, cli.source), ...supplementaryFiles] })
		}
		splitConfig = configManager.getSplitConfig()
		brandPlatformConfig = configManager.getBrandPlatformConfig()
	} catch (error) {
		console.error(`\n[design-tokens] invalid arguments or config: ${error.message}`)
		process.exit(1)
	}

	const { brands, platforms, buildPathPrefix, tempDir, brandSets } = brandPlatformConfig

	if (!cli.skipSplit) {
		console.log(`[design-tokens] using source(s): ${splitConfig.inputFiles.join(', ')}`)
		try {
			await splitDesignTokens(splitConfig)
		} catch (error) {
			console.error(`\n[design-tokens] split failed: ${error.message}`)
			process.exit(1)
		}
	} else {
		console.log('[design-tokens] --skip-split: reusing existing temp/ files')
	}

	// Build into a fresh staging dir, then swap it in: removed tokens / renamed
	// files don't linger, and a failed build keeps the previous `dist/`.
	const stagingPath = path.join(tempDir, 'dist-staging')
	await fs.rm(stagingPath, { recursive: true, force: true })
	try {
		await buildBrands(brands, { buildPathPrefix: stagingPath, tempDir, platforms, brandSets, verbose: cli.verbose })
	} catch (error) {
		await fs.rm(stagingPath, { recursive: true, force: true })
		console.error(`\n[design-tokens] style-dictionary build failed: ${error.message}\nRerun with --verbose for details.`)
		process.exit(1)
	}
	try {
		// `cp` rather than `rename`: works across devices.
		await fs.rm(buildPathPrefix, { recursive: true, force: true })
		await fs.cp(stagingPath, buildPathPrefix, { recursive: true })
		await fs.rm(stagingPath, { recursive: true, force: true })
	} catch (error) {
		console.error(`\n[design-tokens] copying the build into ${buildPathPrefix} failed: ${error.message}`)
		process.exit(1)
	}

	console.log('\n[design-tokens] build complete.')
}

await exec(process.argv.slice(2))
EOF

	cat >token-config.js <<'EOF'
/**
 * @fileoverview
 * Design tokens build configuration.
 *
 * Drives the splitter and Style Dictionary build for `@repo/design-tokens`.
 * Adapted from the multi-brand POC at https://github.com/orioltf/poc-tokens
 * and trimmed for a Tailwind-v4-first setup. Builds one brand by default.
 * Unknown keys fail the build.
 *
 * To add a brand: append to `brands` and (optionally) configure per-brand
 * set inclusion via `brandSets`. To add a platform: implement a factory in
 * `lib/platformConfigs.mjs`, register it in `PLATFORM_FACTORIES` and add its
 * key to `platforms`. Path keys (`sourcePathPrefix`, `buildPathPrefix`,
 * `tempDir`) default to `tokens/`, `dist/` and `temp/`; `tempDir` must not be
 * inside `buildPathPrefix`. The build deletes and recreates `buildPathPrefix`
 * on every run, so point it only at a folder the build owns. The package
 * `exports` assume `dist/`; update them if you move it.
 */

export default {
	/**
	 * Brands to build, one bundle per brand. The first brand builds to `dist/`
	 * (the package `exports`); each further brand builds to `dist/<brand>/`.
	 */
	brands: ['brandName'],

	/**
	 * Platforms to build per brand. Keep minimal — Tailwind v4 `@theme`
	 * is the runtime contract; `css-vars` is kept for raw-CSS consumers.
	 *
	 * The `js` platform exists in `lib/platformConfigs.mjs` but is OFF by
	 * default because Tokens Studio exports often contain token names that
	 * start with a digit (e.g. a `2` key in a viewport set), which are invalid
	 * JS identifiers. Add `'js'` back once token naming is normalized, and add
	 * a `"."` entry for `dist/index.*` to the package `exports`.
	 */
	platforms: ['tailwind-css', 'css-vars'],

	/**
	 * Token source files. The splitter reads all files, merges their top-level
	 * sets into a single map, then writes one temp file per set. Paths are
	 * relative to `tokens/` (or absolute). Each file must be a single-file
	 * Tokens Studio export; a set name in two files fails the build. `pnpm
	 * build --source=PATH` replaces the first entry only.
	 */
	inputFiles: ['primitive-design-tokens.json'],

	/**
	 * Token-set splitting strategy.
	 *
	 * `$`-prefixed Tokens Studio metadata (`$themes`, `$metadata`) is always
	 * skipped.
	 *
	 * - `excludeKeys`: drop these top-level sets before splitting. Tokens
	 *   Studio puts new tokens in `global`, so exclude it only when it is empty
	 *   or unused.
	 * - `includeKeys`: if non-empty, ONLY these sets are split. Mutually
	 *   exclusive with `excludeKeys`, so empty `excludeKeys` when you set it.
	 */
	excludeKeys: [],
	includeKeys: [],

	/**
	 * Per-brand set selection. Maps brand → array of set-file basenames
	 * (without `.json`). Slashes in Tokens Studio set names become
	 * underscores in filenames (e.g. `Theme/Brand Light` → `Theme_Brand Light`).
	 * An unknown basename, or a key that is not in `brands`, fails the build.
	 *
	 * IMPORTANT: split files hold the set contents without the set name, so
	 * two theme sets that define the same token paths (Light + Dark) collide
	 * when loaded together, and a collision fails the build. Pick ONE theme
	 * variant per brand here, plus any non-theme support sets (Components,
	 * Viewport, etc.).
	 *
	 * A brand without an entry uses all split files.
	 */
	brandSets: {},
}
EOF

	printf 'dist/\ntemp/\n' >.gitignore

	log_success "Design tokens build pipeline added"
}

add_design_tokens_sample() {
	log_info "Adding sample primitive tokens (DTCG format)..."
	cd "$TARGET_FOLDER/packages/design-tokens" || exit

	mkdir -p tokens

	cat >tokens/primitive-design-tokens.json <<'EOF'
{
  "$metadata": { "tokenSetOrder": ["Primitives"] },
  "$themes": [],
  "Primitives": {
    "color": {
      "primary": {
        "50":  { "$value": "#eff6ff", "$type": "color" },
        "100": { "$value": "#dbeafe", "$type": "color" },
        "200": { "$value": "#bfdbfe", "$type": "color" },
        "300": { "$value": "#93c5fd", "$type": "color" },
        "400": { "$value": "#60a5fa", "$type": "color" },
        "500": { "$value": "#3b82f6", "$type": "color" },
        "600": { "$value": "#2563eb", "$type": "color" },
        "700": { "$value": "#1d4ed8", "$type": "color" },
        "800": { "$value": "#1e40af", "$type": "color" },
        "900": { "$value": "#1e3a8a", "$type": "color" },
        "950": { "$value": "#172554", "$type": "color" }
      },
      "neutral": {
        "50":  { "$value": "#fafafa", "$type": "color" },
        "100": { "$value": "#f4f4f5", "$type": "color" },
        "200": { "$value": "#e4e4e7", "$type": "color" },
        "300": { "$value": "#d4d4d8", "$type": "color" },
        "400": { "$value": "#a1a1aa", "$type": "color" },
        "500": { "$value": "#71717a", "$type": "color" },
        "600": { "$value": "#52525b", "$type": "color" },
        "700": { "$value": "#3f3f46", "$type": "color" },
        "800": { "$value": "#27272a", "$type": "color" },
        "900": { "$value": "#18181b", "$type": "color" },
        "950": { "$value": "#09090b", "$type": "color" }
      }
    },
    "spacing": {
      "0":   { "$value": "0",         "$type": "dimension" },
      "px":  { "$value": "1px",       "$type": "dimension" },
      "0-5": { "$value": "0.125rem",  "$type": "dimension" },
      "1":   { "$value": "0.25rem",   "$type": "dimension" },
      "1-5": { "$value": "0.375rem",  "$type": "dimension" },
      "2":   { "$value": "0.5rem",    "$type": "dimension" },
      "2-5": { "$value": "0.625rem",  "$type": "dimension" },
      "3":   { "$value": "0.75rem",   "$type": "dimension" },
      "3-5": { "$value": "0.875rem",  "$type": "dimension" },
      "4":   { "$value": "1rem",      "$type": "dimension" },
      "5":   { "$value": "1.25rem",   "$type": "dimension" },
      "6":   { "$value": "1.5rem",    "$type": "dimension" },
      "7":   { "$value": "1.75rem",   "$type": "dimension" },
      "8":   { "$value": "2rem",      "$type": "dimension" },
      "9":   { "$value": "2.25rem",   "$type": "dimension" },
      "10":  { "$value": "2.5rem",    "$type": "dimension" },
      "12":  { "$value": "3rem",      "$type": "dimension" },
      "14":  { "$value": "3.5rem",    "$type": "dimension" },
      "16":  { "$value": "4rem",      "$type": "dimension" },
      "20":  { "$value": "5rem",      "$type": "dimension" },
      "24":  { "$value": "6rem",      "$type": "dimension" },
      "32":  { "$value": "8rem",      "$type": "dimension" }
    },
    "typography": {
      "font-family": {
        "sans": { "$value": ["Inter", "system-ui", "sans-serif"],     "$type": "fontFamily" },
        "mono": { "$value": ["JetBrains Mono", "Menlo", "monospace"], "$type": "fontFamily" }
      },
      "font-size": {
        "xs":   { "$value": "0.75rem",  "$type": "dimension" },
        "sm":   { "$value": "0.875rem", "$type": "dimension" },
        "base": { "$value": "1rem",     "$type": "dimension" },
        "lg":   { "$value": "1.125rem", "$type": "dimension" },
        "xl":   { "$value": "1.25rem",  "$type": "dimension" },
        "2xl":  { "$value": "1.5rem",   "$type": "dimension" },
        "3xl":  { "$value": "1.875rem", "$type": "dimension" },
        "4xl":  { "$value": "2.25rem",  "$type": "dimension" }
      },
      "font-weight": {
        "normal":   { "$value": "400", "$type": "fontWeight" },
        "medium":   { "$value": "500", "$type": "fontWeight" },
        "semibold": { "$value": "600", "$type": "fontWeight" },
        "bold":     { "$value": "700", "$type": "fontWeight" }
      },
      "line-height": {
        "none":    { "$value": "1",     "$type": "number" },
        "tight":   { "$value": "1.25",  "$type": "number" },
        "snug":    { "$value": "1.375", "$type": "number" },
        "normal":  { "$value": "1.5",   "$type": "number" },
        "relaxed": { "$value": "1.625", "$type": "number" },
        "loose":   { "$value": "2",     "$type": "number" }
      }
    },
    "semantic": {
      "background": {
        "default": { "$value": "{color.neutral.50}",  "$type": "color" },
        "muted":   { "$value": "{color.neutral.100}", "$type": "color" },
        "subtle":  { "$value": "{color.neutral.200}", "$type": "color" },
        "inverse": { "$value": "{color.neutral.900}", "$type": "color" }
      },
      "foreground": {
        "default": { "$value": "{color.neutral.900}", "$type": "color" },
        "muted":   { "$value": "{color.neutral.600}", "$type": "color" },
        "subtle":  { "$value": "{color.neutral.400}", "$type": "color" },
        "inverse": { "$value": "{color.neutral.50}",  "$type": "color" }
      },
      "border": {
        "default": { "$value": "{color.neutral.200}", "$type": "color" },
        "muted":   { "$value": "{color.neutral.100}", "$type": "color" },
        "strong":  { "$value": "{color.neutral.300}", "$type": "color" }
      },
      "accent": {
        "default": { "$value": "{color.primary.500}", "$type": "color" },
        "hover":   { "$value": "{color.primary.600}", "$type": "color" },
        "active":  { "$value": "{color.primary.700}", "$type": "color" },
        "muted":   { "$value": "{color.primary.100}", "$type": "color" }
      }
    }
  }
}
EOF

	log_success "Sample primitive tokens added"
}

add_design_tokens_tsconfig() {
	log_info "Adding TypeScript configuration for design-tokens..."
	cd "$TARGET_FOLDER/packages/design-tokens" || exit

	cat >tsconfig.json <<'EOF'
{
  "extends": "@repo/typescript-config/base.json",
  "compilerOptions": {
    "outDir": "dist",
    "rootDir": ".",
    "declaration": true,
    "declarationMap": true,
    "module": "ESNext",
    "moduleResolution": "bundler",
    "target": "ES2022",
    "allowJs": true
  },
  "include": ["token-config.js", "lib/**/*.mjs", "scripts/**/*.mjs", "tokens/**/*.json"],
  "exclude": ["node_modules", "dist"]
}
EOF

	log_success "TypeScript configuration added"
}

add_design_tokens_readme() {
	log_info "Creating design-tokens README.md..."
	cd "$TARGET_FOLDER/packages/design-tokens" || exit

	cat >README.md <<'EOF'
# `@repo/design-tokens`

Design tokens for the Design System, built with [Style Dictionary](https://styledictionary.com/) and a modular [Tokens Studio](https://tokens.studio/) split-and-build pipeline.

## Overview

The build runs in two stages:

1. **Split** — `scripts/split-design-tokens.mjs` reads one or more Tokens Studio JSON exports, merges their top-level "sets", and writes each set to its own file in `temp/`.
2. **Build** — `scripts/build-style-dictionary.mjs` invokes Style Dictionary once per configured brand, using the appropriate set files for that brand, and emits outputs to `dist/`.

The pipeline uses the [`@tokens-studio/sd-transforms`](https://github.com/tokens-studio/sd-transforms) preprocessor. The splitter already removes each set-name wrapper, so token paths start at the first group inside a set (`color.neutral.50` → `--color-neutral-50`). Tailwind v4 `@theme` is the primary runtime contract; plain CSS variables are also emitted, and a JS/TS output platform is available but disabled by default.

## File Layout

```
design-tokens/
├── lib/                              # Build engine (modular ESM)
│   ├── buildBrands.mjs               # Brand × platform orchestrator
│   ├── configManager.mjs             # Loads token-config.js over defaults
│   ├── platformConfigs.mjs           # Per-platform Style Dictionary factories
│   └── registerTransforms.mjs        # Tokens Studio preprocessor + custom formats
├── scripts/                          # CLI entry points
│   ├── build-style-dictionary.mjs    # Main build (split + per-brand SD run)
│   └── split-design-tokens.mjs       # Splitter (`pnpm split-tokens`)
├── tokens/                           # Tokens Studio source files
│   └── primitive-design-tokens.json  # Default primitive palette
├── temp/                             # Per-set intermediate files (package .gitignore)
├── dist/                             # Build outputs (package .gitignore)
├── token-config.js                   # User-editable build config
├── tsconfig.json
└── package.json
```

## Configuring the build

Edit `token-config.js`:

| Field         | Type                       | Purpose                                                                                                                                            |
| ------------- | -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `brands`      | `string[]`                 | One bundle per brand. The first brand → `dist/` (the `css` and `tailwind-theme` exports). Further brands → `dist/<brand>/`.                     |
| `platforms`   | `string[]`                 | Output formats. Known keys: `tailwind-css`, `css-vars`, `js`.                                                                                      |
| `inputFiles`  | `string[]`                 | Single-file Tokens Studio exports (relative to `tokens/` or absolute), merged. A set name in two files fails the build.                         |
| `excludeKeys` | `string[]`                 | Top-level sets to drop before splitting (e.g. an unused `global`). `$`-prefixed metadata is always dropped. Mutually exclusive with `includeKeys`.         |
| `includeKeys` | `string[]`                 | If non-empty, ONLY these top-level keys are split.                                                                                                 |
| `brandSets`   | `Record<string, string[]>` | Per-brand selection of split-file basenames (without `.json`). Slashes in set names become underscores. No entry → use all. Unknown names and set collisions fail the build. |

### Available platforms

| Key            | Outputs                                              | Use case                                                       |
| -------------- | ---------------------------------------------------- | -------------------------------------------------------------- |
| `tailwind-css` | `dist/tailwind-theme.css`                            | Tailwind v4 `@theme` block (primary runtime contract).         |
| `css-vars`     | `dist/tokens.css`                                    | Plain `:root { --token: value }` for non-Tailwind consumers.   |
| `js`           | `dist/index.js`, `dist/index.cjs`, `dist/index.d.ts` | Named JS exports with `.d.ts`. Off by default — enable when token names are valid JS identifiers, and add a `"."` entry to `exports`. |

## Usage

### Tailwind CSS v4

```css
@import "tailwindcss";
@import "@repo/design-tokens/tailwind-theme";
```

### Plain CSS

```css
@import "@repo/design-tokens/css";

.button {
  background-color: var(--semantic-accent-default);
  color: var(--semantic-foreground-inverse);
}
```

### JavaScript (after enabling the `js` platform)

```typescript
import { colorPrimary500 } from "@repo/design-tokens";
```

## Development

```sh
# Full pipeline: split + per-brand Style Dictionary build
pnpm build

# Watch tokens, token-config.js, lib/, scripts/ — rebuild on change
pnpm build:watch

# Run just the splitter (debugging)
pnpm split-tokens

# Wipe dist/ and temp/
pnpm clean
```

### CLI flags on `pnpm build`

| Flag            | Effect                                                            |
| --------------- | ----------------------------------------------------------------- |
| `--source=PATH` | Override `inputFiles[0]` with this path, absolute or relative to where you run `pnpm`. Needs the `=`. |
| `--skip-split`  | Reuse existing `temp/` contents (rapid rebuild during iteration). |
| `--verbose`     | Verbose Style Dictionary logging, e.g. to name broken references. |

## Tokens Studio integration

Tokens are nested groups whose leaves carry W3C DTCG `$value` / `$type` (the sample) or the legacy Tokens Studio `value` / `type`, with references like `{color.neutral.50}`. Drop the export at `tokens/<your-export>.json` and replace `primitive-design-tokens.json` in `inputFiles` with its filename. You can then delete the sample. Each input file needs the `$metadata` of a single-file export, and all `inputFiles` must use one format: a mix fails the build.

### Adding a new brand

1. Append the brand name to `brands` in `token-config.js`.
2. Optionally add a `brandSets[<brand>]` entry listing the set basenames to include (e.g. `Theme_Brand Light`, `Primitives`, `Components_Mode`).
3. Run `pnpm build`. The first brand stays at `dist/`; each further brand emits to `dist/<brand>/` and imports as `@repo/design-tokens/<brand>/tailwind-theme.css` (and `<brand>/tokens.css` with `css-vars`).

### Adding a new platform

1. Implement a factory in `lib/platformConfigs.mjs`.
2. Register it in the `PLATFORM_FACTORIES` map.
3. Add its key to `platforms` in `token-config.js`.
EOF

	log_success "design-tokens README.md created"
}
