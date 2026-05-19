#!/usr/bin/env bash

# =============================================================================
# Prettier Package Module
# =============================================================================
# Functions for creating the @repo/prettier-config package

create_prettier_config_package() {
	log_info "Creating @repo/prettier-config package..."
	cd "$TARGET_FOLDER/packages" || exit

	mkdir -p prettier-config
	cd prettier-config || exit

	pnpm init --bare

	jq \
		--arg name "@repo/prettier-config" \
		--arg description "Shared Prettier configuration for the ${ORGANIZATION_NAME} Design System monorepo" \
		--arg author "${DEVELOPER}" \
		'. + {
			name: $name,
			version: "1.0.0",
			description: $description,
			author: $author,
			license: "LGPL-3.0-or-later",
			type: "module",
			private: true,
			main: "base.js",
			files: ["base.js"],
			exports: { ".": "./base.js", "./base": "./base.js" }
		}' package.json >package.json.tmp && mv package.json.tmp package.json

	log_success "@repo/prettier-config package created"
}

add_prettier_base_config() {
	log_info "Adding base Prettier configuration..."
	cd "$TARGET_FOLDER/packages/prettier-config" || exit

	cat >base.js <<'EOF'
/**
 * @see https://prettier.io/docs/configuration
 * @type {import("prettier").Config}
 */
const config = {
	semi: false,
	singleQuote: true,
	useTabs: true,
	trailingComma: 'es5',
	printWidth: 120,
	bracketSpacing: true,
	bracketSameLine: false,
	arrowParens: 'always',
	endOfLine: 'lf',
	quoteProps: 'as-needed',
	jsxSingleQuote: false,
	proseWrap: 'preserve',
	htmlWhitespaceSensitivity: 'css',
	embeddedLanguageFormatting: 'auto',
	overrides: [
		{
			files: ['*.json', '*.yml', '*.yaml', '*.feature', '*.md'],
			options: {
				useTabs: false,
				tabWidth: 2,
			},
		},
	],
}

export default config
EOF

	log_success "Base Prettier configuration added"
}

add_prettier_config_readme() {
	log_info "Creating README.md..."
	cd "$TARGET_FOLDER/packages/prettier-config" || exit

	cat >README.md <<'EOF'
# `@repo/prettier-config`

Collection of internal prettier configurations.
EOF

	log_success "README.md created"
}
