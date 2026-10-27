#!/usr/bin/env bash

# =============================================================================
# Design tokens regression check
# =============================================================================
# Generates the design tokens build pipeline and sample into a temp folder,
# builds the sample and the fixtures in tests/fixtures/design-tokens/ and
# checks the CSS output, including every variable the Storybook stories use.
# Also builds two brands and builds from the repo root, checks that invalid
# sets, formats, brands, values and build paths fail with a message, and
# checks the build lock (busy exit code 75, stale lock takeover), that the
# build refuses an output folder it did not write, and that build:watch
# refuses flags. Runs in a folder named `[ds] {work}` to cover glob
# and reference characters. Pins style-dictionary@5 and
# @tokens-studio/sd-transforms@2; generated repos resolve the latest versions
# through the catalog. Needs network for `pnpm add`.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES_DIR="$ROOT_DIR/tests/fixtures/design-tokens"
TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEMP_ROOT"' EXIT
# Style Dictionary reads source paths as globs and `{…}` as token references.
WORK_DIR="$TEMP_ROOT/[ds] {work}"
mkdir -p "$WORK_DIR"

# shellcheck disable=SC1091
source "$ROOT_DIR/lib/utils.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/package-design-tokens.sh"

# shellcheck disable=SC2034 # read by the sourced generator functions
TARGET_FOLDER="$WORK_DIR"
PACKAGE_DIR="$WORK_DIR/packages/design-tokens"
FAILURES=0

expect_css() {
	local file="$1" declaration="$2"
	# Anchor at the start of the declaration, so --a-b: cannot match --x-a-b:.
	if grep -qF -- "$(printf '\t%s' "$declaration")" "$PACKAGE_DIR/dist/$file" || grep -qF -- "  $declaration" "$PACKAGE_DIR/dist/$file"; then
		echo "ok    $file: $declaration"
	else
		echo "FAIL  $file: expected \"$declaration\""
		FAILURES=$((FAILURES + 1))
	fi
}

expect_build_failure() {
	local description="$1" message="$2" output
	if output="$(cd "$PACKAGE_DIR" && node scripts/build-style-dictionary.mjs 2>&1)"; then
		echo "FAIL  $description: build passed"
		FAILURES=$((FAILURES + 1))
	elif grep -qF -- "$message" <<<"$output"; then
		echo "ok    $description"
	else
		echo "FAIL  $description: missing \"$message\""
		FAILURES=$((FAILURES + 1))
	fi
}

set_inputs() {
	sed -i.bak "s|inputFiles: \[.*\],|inputFiles: [$1],|" "$PACKAGE_DIR/token-config.js"
}

build_with_inputs() {
	set_inputs "$1"
	# A failed build keeps the previous dist/, which would satisfy the checks.
	rm -rf "$PACKAGE_DIR/dist"
	local output
	if ! output="$(cd "$PACKAGE_DIR" && node scripts/build-style-dictionary.mjs 2>&1)"; then
		echo "FAIL  $1: build failed"
		echo "$output" | tail -5
		FAILURES=$((FAILURES + 1))
		return
	fi
	if grep -rnE 'undefined|NaN|\[object Object\]|pxpx' "$PACKAGE_DIR/dist"; then
		echo "FAIL  $1: invalid value in dist/"
		FAILURES=$((FAILURES + 1))
	fi
}

mkdir -p "$PACKAGE_DIR"
add_design_tokens_config >/dev/null
add_design_tokens_sample >/dev/null
cp "$FIXTURES_DIR"/*.json "$PACKAGE_DIR/tokens/"
echo '{ "name": "design-tokens-test", "type": "module", "private": true }' >"$PACKAGE_DIR/package.json"
(cd "$PACKAGE_DIR" && pnpm add --silent style-dictionary@5 @tokens-studio/sd-transforms@2)

build_with_inputs "'primitive-design-tokens.json'"
STORYBOOK_VARIABLES="$(grep -ohE 'var\(--[a-z0-9-]+' "$ROOT_DIR/lib/package-storybook.sh" | sort -u | sed 's/var(//')"
if [[ -z "$STORYBOOK_VARIABLES" ]]; then
	echo "FAIL  found no var(--...) in lib/package-storybook.sh"
	FAILURES=$((FAILURES + 1))
fi
while read -r variable; do
	expect_css tokens.css "$variable:"
done <<<"$STORYBOOK_VARIABLES"
expect_css tokens.css "--semantic-accent-default: var(--color-primary-500);"
expect_css tailwind-theme.css "--semantic-accent-default: #3b82f6;"

# From the repo root, as a script without pnpm would run it.
rm -rf "$PACKAGE_DIR/dist"
if (cd "$WORK_DIR" && node packages/design-tokens/scripts/build-style-dictionary.mjs >/dev/null 2>&1); then
	expect_css tokens.css "--semantic-accent-default: var(--color-primary-500);"
else
	echo "FAIL  build from the repo root"
	FAILURES=$((FAILURES + 1))
fi

build_with_inputs "'legacy.json'"
expect_css tokens.css "--line-heights-relaxed: 1.5;"
expect_css tokens.css "--line-heights-body: var(--line-heights-relaxed);"
expect_css tokens.css "--line-heights-fixed: 24px;"
expect_css tokens.css "--line-heights-math: 24px;"
expect_css tokens.css "--line-heights-auto: normal;"
expect_css tokens.css "--letter-spacing-tight: -0.5px;"
expect_css tokens.css "--letter-spacing-wide: 0.05em;"
expect_css tokens.css "--spacing-multi: 8px 16px;"
expect_css tokens.css "--typography-body-line-height: var(--line-heights-relaxed);"
expect_css tokens.css "--typography-body-letter-spacing: -0.32px;"
expect_css tokens.css "--card-padding-top: 8px 16px;"
expect_css tokens.css "--card-line-heights: 24px;"
expect_css tailwind-theme.css "--line-heights-computed: 24px;"
expect_css tailwind-theme.css "--typography-heading-line-height: 24px;"
expect_css tailwind-theme.css "--typography-body-line-height: 1.5;"
expect_css tailwind-theme.css "--typography-paragraph-line-height: 1.5;"
expect_css tailwind-theme.css "--panel-typography-line-height: 1.5;"

build_with_inputs "'dtcg.json'"
expect_css tokens.css "--heading-line-height: var(--scale-leading);"
expect_css tokens.css "--heading-letter-spacing: -0.5px;"
expect_css tokens.css "--leading-direct: 1.5;"
expect_css tailwind-theme.css "--subheading-line-height: 1.5;"
expect_css tailwind-theme.css "--panel-typography-line-height: 1.5;"
expect_css tailwind-theme.css "--value: 1.4;"
expect_css tokens.css "--spacing-value: 4px;"
expect_css tokens.css "--note: #123456; /** Use for borders * / and dividers */"

sed -i.bak "s|brands: \['brandName'\],|brands: ['a', 'b'],|; s|brandSets: {},|brandSets: { a: ['Brand_A'], b: ['Brand_B'] },|" "$PACKAGE_DIR/token-config.js"
build_with_inputs "'brands.json'"
expect_css tailwind-theme.css "--line-heights-body: 1.5;"
expect_css b/tailwind-theme.css "--line-heights-body: 24px;"
sed -i.bak "s|brands: \['a', 'b'\],|brands: ['brandName'],|; s|brandSets: { a: \['Brand_A'\], b: \['Brand_B'\] },|brandSets: {},|" "$PACKAGE_DIR/token-config.js"

set_inputs "'themes.json'"
expect_build_failure "two themes of one brand collide" "one theme set per brand) in brandSets"

set_inputs "'legacy.json', 'dtcg.json'"
expect_build_failure "mixed DTCG and legacy inputs" "Export all inputFiles in one format"

set_inputs "'mixed.json'"
expect_build_failure "mixed formats in one export" "mixes DTCG \$value/\$type and legacy value/type tokens"

set_inputs "'braces.json'"
expect_build_failure "braces in a set name" "are not allowed in set names"

set_inputs "'colon.json'"
expect_build_failure "set name that is not a file name everywhere" "cannot be a file name on every system"

set_inputs "'case.json'"
expect_build_failure "sets that differ only in case" "both map to"

set_inputs "'gradient.json'"
expect_build_failure "object values without a CSS form" "Rerun with --verbose"

set_inputs "'primitive-design-tokens.json'"
sed -i.bak "s|brandSets: {},|brandSets: {}, buildPathPrefix: 'lib',|" "$PACKAGE_DIR/token-config.js"
expect_build_failure "build path over lib/" "buildPathPrefix must not be or hold the package folder"
sed -i.bak "s|brandSets: {}, buildPathPrefix: 'lib',|brandSets: {},|" "$PACKAGE_DIR/token-config.js"

sed -i.bak "s|brandSets: {},|brandSets: {}, sourcePathPrefix: 'dist/..tokens',|" "$PACKAGE_DIR/token-config.js"
expect_build_failure "sources in a folder named ..tokens inside dist/" "must not be or hold the package folder"
sed -i.bak "s|brandSets: {}, sourcePathPrefix: 'dist/..tokens',|brandSets: {},|" "$PACKAGE_DIR/token-config.js"

sed -i.bak "s|brandSets: {},|brandSets: {}, buildPathPrefix: 'temp/dist-staging',|" "$PACKAGE_DIR/token-config.js"
expect_build_failure "build path inside tempDir" "buildPathPrefix must not be inside tempDir"
sed -i.bak "s|brandSets: {}, buildPathPrefix: 'temp/dist-staging',|brandSets: {},|" "$PACKAGE_DIR/token-config.js"

sed -i.bak "s|brands: \['brandName'\],|brands: ['a', '../../tokens'],|" "$PACKAGE_DIR/token-config.js"
expect_build_failure "brand name that is a path" "Brand names must be plain folder names"
sed -i.bak "s|brands: \['a', '../../tokens'\],|brands: ['a', 'Acme', 'acme'],|" "$PACKAGE_DIR/token-config.js"
expect_build_failure "brands that differ only in case" "differ only in case"
sed -i.bak "s|brands: \['a', 'Acme', 'acme'\],|brands: ['brandName'],|" "$PACKAGE_DIR/token-config.js"

# In the background with a kill after 2 s: a watcher that accepts the flag
# would otherwise run until the test is stopped.
(cd "$PACKAGE_DIR" && node scripts/watch.mjs --source=tokens/legacy.json >"$WORK_DIR/watch.log" 2>&1) &
WATCH_PID=$!
sleep 2
kill "$WATCH_PID" 2>/dev/null || true
wait "$WATCH_PID" 2>/dev/null || true
if grep -qF "takes no flags" "$WORK_DIR/watch.log"; then
	echo "ok    build:watch refuses flags"
else
	echo "FAIL  build:watch should refuse flags"
	FAILURES=$((FAILURES + 1))
fi

mkdir -p "$WORK_DIR/shared-styles"
echo "keep me" >"$WORK_DIR/shared-styles/globals.css"
sed -i.bak "s|brandSets: {},|brandSets: {}, buildPathPrefix: '../../shared-styles',|" "$PACKAGE_DIR/token-config.js"
expect_build_failure "build path over a folder the build did not write" "holds files the build did not write"
sed -i.bak "s|brandSets: {}, buildPathPrefix: '../../shared-styles',|brandSets: {},|" "$PACKAGE_DIR/token-config.js"
if [[ -f "$WORK_DIR/shared-styles/globals.css" ]]; then echo "ok    shared folder kept"; else
	echo "FAIL  shared folder lost globals.css"
	FAILURES=$((FAILURES + 1))
fi

mkdir -p "$PACKAGE_DIR/temp/.build-lock"
echo "$$" >"$PACKAGE_DIR/temp/.build-lock/pid"
expect_build_failure "overlapping build" "Another build (pid $$)"
BUSY_CODE=0
(cd "$PACKAGE_DIR" && node scripts/build-style-dictionary.mjs >/dev/null 2>&1) || BUSY_CODE=$?
if [[ "$BUSY_CODE" -eq 75 ]]; then
	echo "ok    a busy lock exits with 75"
else
	echo "FAIL  a busy lock should exit with 75, got $BUSY_CODE"
	FAILURES=$((FAILURES + 1))
fi

sleep 0 &
DEAD_PID=$!
wait "$DEAD_PID"
echo "$DEAD_PID" >"$PACKAGE_DIR/temp/.build-lock/pid"
build_with_inputs "'primitive-design-tokens.json'"
if [[ -e "$PACKAGE_DIR/temp/.build-lock" ]]; then
	echo "FAIL  stale lock: still present after the build"
	FAILURES=$((FAILURES + 1))
else
	echo "ok    stale lock taken over and released"
fi

if [[ "$FAILURES" -gt 0 ]]; then
	log_error "$FAILURES design tokens check(s) failed"
	exit 1
fi
log_success "All design tokens checks passed"
