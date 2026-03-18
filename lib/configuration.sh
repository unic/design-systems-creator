#!/usr/bin/env bash

# =============================================================================
# Configuration Module
# =============================================================================
# Functions for creating root-level configuration files:
# - LICENSE
# - .editorconfig
# - ESLint config
# - Prettier config
# - .prettierignore

create_license() {
	log_info "Creating LICENSE file..."
	cd "$TARGET_FOLDER" || exit

	curl -s https://spdx.org/licenses/LGPL-3.0-or-later.json | jq -r '.licenseText' >LICENSE.txt
	log_success "LICENSE file created"
}

create_editorconfig() {
	log_info "Creating .editorconfig..."
	cd "$TARGET_FOLDER" || exit

	cat >.editorconfig <<'EOF'
root = true

[*]
indent_style = tab
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true

[*.md]
trim_trailing_whitespace = false
indent_style = space
indent_size = 2

[{*.json,*.yml,*.yaml,*.feature}]
indent_style = space
indent_size = 2
EOF

	log_success ".editorconfig created"
}

create_eslint_config() {
	log_info "Creating eslint.config.mjs..."
	cd "$TARGET_FOLDER" || exit

	cat >eslint.config.mjs <<'EOF'
import { config } from "@repo/eslint-config/base";

/** @type {import("eslint").Linter.Config} */
export default config;
EOF
	log_success "eslint.config.mjs created"
}

create_prettier_config() {
	log_info "Creating prettier.config.mjs..."
	cd "$TARGET_FOLDER" || exit

	cat >prettier.config.mjs <<'EOF'
import config from "@repo/prettier-config/base"

export default config;
EOF

	log_success "prettier.config.mjs created"
}

create_prettier_ignore() {
	log_info "Creating .prettierignore..."
	cd "$TARGET_FOLDER" || exit

	cat >.prettierignore <<'EOF'
# Dependencies
node_modules/
pnpm-lock.yaml

# Build outputs
dist/
build/
.next/
storybook-static/
coverage/

# Cache
.turbo/
.cache/

# Generated files
*.generated.*
temp/

# Sitecore
.sitecore/

# Other
.history
EOF

	log_success ".prettierignore created"
}
