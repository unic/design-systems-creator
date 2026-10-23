#!/usr/bin/env bash

# =============================================================================
# Design tokens regression check
# =============================================================================
# Generates the design tokens build pipeline and sample into a temp folder,
# builds the sample and the fixtures in tests/fixtures/design-tokens/, checks
# CSS output (including every variable the Storybook stories use) and checks
# that colliding themes and mixed formats fail. Needs network for `pnpm add`.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES_DIR="$ROOT_DIR/tests/fixtures/design-tokens"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

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
	if grep -qF -- "$declaration" "$PACKAGE_DIR/dist/$file"; then
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
	(cd "$PACKAGE_DIR" && node scripts/build-style-dictionary.mjs >/dev/null)
	if grep -nE 'undefined|NaN|\[object Object\]|pxpx' "$PACKAGE_DIR"/dist/*.css; then
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

set_inputs "'themes.json'"
expect_build_failure "two themes of one brand collide" "one theme set per brand) in brandSets"

set_inputs "'legacy.json', 'dtcg.json'"
expect_build_failure "mixed DTCG and legacy inputs" "Export all inputFiles in one format"

if [[ "$FAILURES" -gt 0 ]]; then
	log_error "$FAILURES design tokens check(s) failed"
	exit 1
fi
log_success "All design tokens checks passed"
