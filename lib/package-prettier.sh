#!/usr/bin/env bash

# =============================================================================
# Prettier Package Module
# =============================================================================
# Functions for creating the @repo/prettier-config package

create_prettier_config_package() {
	log_info "Creating @repo/prettier-config package..."
	cd "$TARGET_FOLDER/packages"

	mkdir -p prettier-config
	cd prettier-config

	NPM_CONFIG_INIT_LICENSE="LGPL-3.0-or-later" \
		NPM_CONFIG_INIT_AUTHOR_NAME="${DEVELOPER}" \
		NPM_CONFIG_INIT_DESCRIPTION="Shared Prettier configuration for the ${ORGANIZATION_NAME} Design System monorepo" \
		NPM_CONFIG_INIT_VERSION="1.0.0" \
		NPM_CONFIG_INIT_NAME="@repo/prettier-config" \
		NPM_CONFIG_INIT_TYPE="module" \
		NPM_CONFIG_INIT_EXPORTS="./base.js" \
		NPM_CONFIG_INIT_FILES="base.js" \
		NPM_CONFIG_INIT_MAIN="base.js" \
		NPM_CONFIG_INIT_PRIVATE="true" \
		pnpm init

	log_success "@repo/prettier-config package created"
}

add_prettier_base_config() {
	log_info "Adding base Prettier configuration..."
	cd "$TARGET_FOLDER/packages/prettier-config"

	cat > base.js <<'EOF'
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
	cd "$TARGET_FOLDER/packages/prettier-config"

	cat > README.md <<'EOF'
# `@repo/prettier-config`

Collection of internal prettier configurations.
EOF

	log_success "README.md created"
}
