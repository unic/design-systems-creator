#!/usr/bin/env bash

# Finma Design System Monorepo Setup Script
# This script bootstraps a complete Turbo monorepo for the Finma Design System

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ORGANIZATION_NAME="finma"
REGISTRY_DOMAIN=""
AZURE_DEVOPS_URL=""
VERCEL_TEAM_ID=""
PROJECT_NAME=""
NODE_LTS_VERSION="24"
PNPM_VERSION="10.23.0"

# Script directory for template access
log_info() {
	echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
	echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $1"
}

print_banner() {
	echo -e "${BLUE}"
	echo "╔═══════════════════════════════════════════════════════════════╗"
	echo "║        Finma Design System Monorepo Setup Script              ║"
	echo "║                                                               ║"
	echo "║  This script will bootstrap a complete Turbo monorepo with:   ║"
	echo "║  • Node.js LTS via nvm                                        ║"
	echo "║  • pnpm workspaces                                            ║"
	echo "║  • Shared configuration packages                              ║"
	echo "║  • React component structure                                  ║"
	echo "║  • Design token system                                        ║"
	echo "║  • Shadcn registry configuration                              ║"
	echo "╚═══════════════════════════════════════════════════════════════╝"
	echo -e "${NC}"
}

show_usage() {
	cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Required:
  --project-name NAME       Project name (used for package naming)

Optional:
  --organization NAME       Organization name (default: finma)
  --registry-domain DOMAIN  Shadcn registry domain (interactive if not provided)
  --azure-devops-url URL    Azure DevOps repository URL
  --vercel-team-id ID       Vercel team ID for deployment linking
  --help                    Show this help message

Examples:
  $(basename "$0") --project-name my-design-system
  $(basename "$0") --project-name my-ds --organization my-org --registry-domain registry.my-org.com

EOF
}

parse_arguments() {
	while [[ $# -gt 0 ]]; do
		case $1 in
			--project-name)
				PROJECT_NAME="$2"
				shift 2
				;;
			--organization)
				ORGANIZATION_NAME="$2"
				shift 2
				;;
			--registry-domain)
				REGISTRY_DOMAIN="$2"
				shift 2
				;;
			--azure-devops-url)
				AZURE_DEVOPS_URL="$2"
				shift 2
				;;
			--vercel-team-id)
				VERCEL_TEAM_ID="$2"
				shift 2
				;;
			--help)
				show_usage
				exit 0
				;;
			*)
				log_error "Unknown option: $1"
				show_usage
				exit 1
				;;
		esac
	done

	if [[ -z "$PROJECT_NAME" ]]; then
		log_error "Project name is required. Use --project-name to specify."
		show_usage
		exit 1
	fi
}

prompt_registry_domain() {
	if [[ -z "$REGISTRY_DOMAIN" ]]; then
		echo ""
		log_info "Shadcn Registry Domain Configuration"
		echo "The registry domain is used for distributing components, tokens, and utilities."
		echo "Examples: registry.unic.com, components.example.com"
		echo ""
		read -rp "Enter registry domain (or press Enter for 'registry.unic.com'): " input
		REGISTRY_DOMAIN="${input:-registry.unic.com}"
	fi
	log_info "Using registry domain: $REGISTRY_DOMAIN"
}

check_nvm() {
	log_info "Checking for nvm installation..."
	
	# Source nvm if available
	export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
	if [[ -s "$NVM_DIR/nvm.sh" ]]; then
		# shellcheck source=/dev/null
		source "$NVM_DIR/nvm.sh"
	fi

	if ! command -v nvm &> /dev/null; then
		log_error "nvm is not installed. Please install nvm first:"
		echo "  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash"
		exit 1
	fi
	
	log_success "nvm found"
}

setup_nodejs() {
	log_info "Setting up Node.js LTS v${NODE_LTS_VERSION}..."
	
	# Check if the LTS version is installed
	if ! nvm ls "$NODE_LTS_VERSION" &> /dev/null; then
		log_info "Installing Node.js LTS v${NODE_LTS_VERSION}..."
		nvm install "$NODE_LTS_VERSION"
	fi
	
	# Use the LTS version
	nvm use "$NODE_LTS_VERSION"
	
	# Get the exact version for .nvmrc
	NODE_EXACT_VERSION=$(node --version | sed 's/v//')
	log_success "Node.js v${NODE_EXACT_VERSION} is now active"
}

setup_pnpm() {
	log_info "Setting up pnpm v${PNPM_VERSION}..."
	
	if ! command -v pnpm &> /dev/null; then
		log_info "Installing pnpm..."
		corepack enable
		corepack prepare "pnpm@${PNPM_VERSION}" --activate
	else
		CURRENT_PNPM_VERSION=$(pnpm --version)
		if [[ "$CURRENT_PNPM_VERSION" != "$PNPM_VERSION" ]]; then
			log_info "Updating pnpm from v${CURRENT_PNPM_VERSION} to v${PNPM_VERSION}..."
			corepack prepare "pnpm@${PNPM_VERSION}" --activate
		fi
	fi
	
	log_success "pnpm v${PNPM_VERSION} is ready"
}

create_directory_structure() {
	log_info "Creating directory structure..."
	
	# Config packages
	mkdir -p packages/config/eslint
	mkdir -p packages/config/prettier
	mkdir -p packages/config/typescript
	
	# React component packages
	mkdir -p packages/react/button/src
	mkdir -p packages/react/button/stories
	mkdir -p packages/react/card/src
	mkdir -p packages/react/card/stories
	mkdir -p packages/react/dialog/src
	mkdir -p packages/react/dialog/stories
	
	# Shared utilities
	mkdir -p packages/shared-utilities/hooks
	mkdir -p packages/shared-utilities/utils
	mkdir -p packages/shared-utilities/types
	
	# Design tokens
	mkdir -p packages/tokens/src/tokens
	mkdir -p packages/tokens/src/figma
	mkdir -p packages/tokens/src/build
	mkdir -p packages/tokens/dist
	
	# Storybook app
	mkdir -p apps/storybook/.storybook
	mkdir -p apps/storybook/stories
	
	# Registry
	mkdir -p registry/tokens/web
	mkdir -p registry/tokens/ios
	mkdir -p registry/tokens/android
	mkdir -p registry/react
	mkdir -p registry/utilities
	
	log_success "Directory structure created"
}

create_nvmrc() {
	log_info "Creating .nvmrc file..."
	echo "$NODE_EXACT_VERSION" > .nvmrc
	log_success ".nvmrc created with Node.js v${NODE_EXACT_VERSION}"
}

create_editorconfig() {
	log_info "Creating .editorconfig..."
	cat > .editorconfig <<'EOF'
root = true

[*]
indent_style = tab
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true

[*.md]
trim_trailing_whitespace = false

[{*.json,*.yml,*.yaml,*.feature}]
indent_style = space
indent_size = 2
EOF
	log_success ".editorconfig created"
}

create_root_package_json() {
	log_info "Creating root package.json..."
	cat > package.json <<EOF
{
	"name": "${PROJECT_NAME}",
	"private": true,
	"packageManager": "pnpm@${PNPM_VERSION}",
	"engines": {
		"node": ">=${NODE_LTS_VERSION}.0.0",
		"pnpm": ">=${PNPM_VERSION}"
	},
	"scripts": {
		"dev": "turbo dev --parallel",
		"build": "turbo build",
		"lint": "turbo lint",
		"test": "turbo test",
		"format": "prettier --write \"**/*.{ts,tsx,js,jsx,json,md}\"",
		"format:check": "prettier --check \"**/*.{ts,tsx,js,jsx,json,md}\"",
		"clean": "turbo clean && rm -rf node_modules",
		"typecheck": "turbo typecheck"
	},
	"devDependencies": {
		"@finma/eslint-config": "workspace:*",
		"@finma/prettier-config": "workspace:*",
		"@finma/typescript-config": "workspace:*",
		"prettier": "^3.5.0",
		"turbo": "^2.6.1"
	}
}
EOF
	log_success "Root package.json created"
}

create_pnpm_workspace() {
	log_info "Creating pnpm-workspace.yaml..."
	cat > pnpm-workspace.yaml <<'EOF'
packages:
  - "apps/*"
  - "packages/*"
  - "packages/config/*"
  - "packages/react/*"
  - "packages/tokens"
  - "packages/shared-utilities"
  - "packages/setup-repo-scripts"

catalog:
  # React ecosystem
  react: ^19.1.0
  react-dom: ^19.1.0
  
  # Build tools
  typescript: ~5.8.3
  tsup: ^8.4.0
  
  # Linting & formatting
  eslint: ^9.33.0
  prettier: ^3.5.0
  
  # Testing
  vitest: ^3.1.0
  "@testing-library/react": ^16.3.0
  
  # Storybook
  storybook: ^8.6.0
  
  # Design tokens
  style-dictionary: ^4.3.0
  
  # Next.js
  next: ^15.5.0
EOF
	log_success "pnpm-workspace.yaml created"
}

create_turbo_json() {
	log_info "Creating turbo.json..."
	cat > turbo.json <<'EOF'
{
	"$schema": "https://turbo.build/schema.json",
	"globalDependencies": [
		".env",
		".env.local",
		".env.production"
	],
	"globalEnv": [
		"NODE_ENV",
		"VERCEL_ENV",
		"FINMA_REGISTRY_DOMAIN"
	],
	"ui": "tui",
	"tasks": {
		"build": {
			"dependsOn": ["^build"],
			"inputs": ["$TURBO_DEFAULT$", ".env*"],
			"outputs": [
				".next/**",
				"!.next/cache/**",
				"dist/**",
				"build/**",
				"storybook-static/**"
			]
		},
		"dev": {
			"cache": false,
			"persistent": true
		},
		"lint": {
			"dependsOn": ["^build"],
			"outputs": []
		},
		"test": {
			"dependsOn": ["build"],
			"outputs": ["coverage/**"]
		},
		"typecheck": {
			"dependsOn": ["^build"],
			"outputs": []
		},
		"clean": {
			"cache": false
		},
		"tokens:build": {
			"dependsOn": [],
			"inputs": ["src/tokens/**", "styled-dictionary.config.js"],
			"outputs": ["dist/**"]
		}
	}
}
EOF
	log_success "turbo.json created"
}

create_tsconfig_base() {
	log_info "Creating tsconfig.base.json..."
	cat > tsconfig.base.json <<'EOF'
{
	"$schema": "https://json.schemastore.org/tsconfig",
	"display": "Base",
	"compilerOptions": {
		"target": "ES2022",
		"lib": ["ES2022", "DOM", "DOM.Iterable"],
		"module": "ESNext",
		"moduleResolution": "bundler",
		"resolveJsonModule": true,
		"allowJs": true,
		"strict": true,
		"noEmit": true,
		"esModuleInterop": true,
		"skipLibCheck": true,
		"forceConsistentCasingInFileNames": true,
		"isolatedModules": true,
		"incremental": true,
		"declaration": true,
		"declarationMap": true,
		"sourceMap": true,
		"verbatimModuleSyntax": true
	},
	"exclude": ["node_modules", "dist", "build", ".next", "coverage"]
}
EOF
	log_success "tsconfig.base.json created"
}

create_tsconfig_root() {
	log_info "Creating tsconfig.json..."
	cat > tsconfig.json <<'EOF'
{
	"extends": "./tsconfig.base.json",
	"compilerOptions": {
		"baseUrl": ".",
		"paths": {
			"@finma/*": ["packages/*/src"]
		}
	},
	"include": ["**/*.ts", "**/*.tsx"],
	"exclude": ["node_modules", "**/node_modules", "dist", "build", ".next"]
}
EOF
	log_success "tsconfig.json created"
}

create_eslint_config() {
	log_info "Creating .eslintrc.cjs..."
	cat > .eslintrc.cjs <<'EOF'
/** @type {import('eslint').Linter.Config} */
module.exports = {
	root: true,
	extends: ["@finma/eslint-config"],
	parserOptions: {
		project: true,
		tsconfigRootDir: __dirname,
	},
	ignorePatterns: [
		"node_modules/",
		"dist/",
		"build/",
		".next/",
		"coverage/",
		"storybook-static/",
	],
};
EOF
	log_success ".eslintrc.cjs created"
}

create_prettier_config() {
	log_info "Creating .prettierrc.cjs..."
	cat > .prettierrc.cjs <<'EOF'
module.exports = require("@finma/prettier-config");
EOF
	log_success ".prettierrc.cjs created"
}

create_prettier_ignore() {
	log_info "Creating .prettierignore..."
	cat > .prettierignore <<'EOF'
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
EOF
	log_success ".prettierignore created"
}

create_env_example() {
	log_info "Creating .env.example..."
	cat > .env.example <<EOF
# Finma Design System Environment Variables
# Copy this file to .env.local and configure your values

# =============================================================================
# Registry Configuration
# =============================================================================

# Shadcn registry domain for component/token distribution
FINMA_REGISTRY_DOMAIN=${REGISTRY_DOMAIN}

# Registry version defaults (can be overridden per-environment)
FINMA_TOKENS_WEB_VERSION=latest
FINMA_TOKENS_IOS_VERSION=latest
FINMA_TOKENS_ANDROID_VERSION=latest
FINMA_REGISTRY_VERSION=latest

# =============================================================================
# Sitecore Configuration (apps/playground)
# =============================================================================

# Sitecore editing secret for securing the editor endpoint
SITECORE_EDITING_SECRET=

# Site configuration
NEXT_PUBLIC_DEFAULT_SITE_NAME=
NEXT_PUBLIC_DEFAULT_LANGUAGE=en

# Sitecore Edge Context (for server-side use)
SITECORE_EDGE_CONTEXT_ID=

# Sitecore Edge Context (for client-side use, fallback)
NEXT_PUBLIC_SITECORE_EDGE_CONTEXT_ID=

# Personalization
NEXT_PUBLIC_PERSONALIZE_SCOPE=
PERSONALIZE_MIDDLEWARE_CDP_TIMEOUT=400
PERSONALIZE_MIDDLEWARE_EDGE_TIMEOUT=400

# Design Library (Sitecore auth)
SITECORE_AUTH_CLIENT_ID=
SITECORE_AUTH_CLIENT_SECRET=

# =============================================================================
# Vercel Configuration
# =============================================================================

# Vercel team ID (optional, for team deployments)
VERCEL_TEAM_ID=${VERCEL_TEAM_ID}

# =============================================================================
# Development
# =============================================================================

# Debug logging for Sitecore Content SDK
# DEBUG=content-sdk:*

# Node environment
NODE_ENV=development
EOF
	log_success ".env.example created"
}

create_vercel_json() {
	log_info "Creating vercel.json..."
	cat > vercel.json <<'EOF'
{
	"$schema": "https://openapi.vercel.sh/vercel.json",
	"buildCommand": "pnpm turbo build --filter=playground --filter=storybook",
	"installCommand": "pnpm install",
	"framework": null,
	"ignoreCommand": "npx turbo-ignore"
}
EOF
	log_success "vercel.json created"
}

create_gitignore_update() {
	log_info "Updating .gitignore..."
	
	# Append additional entries if not already present
	if ! grep -q "# Turbo" .gitignore 2>/dev/null; then
		cat >> .gitignore <<'EOF'

# Turbo
.turbo/

# Build outputs
dist/
build/
storybook-static/

# Environment files
.env
.env.local
.env.*.local

# IDE
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Logs
*.log
npm-debug.log*
pnpm-debug.log*

# Testing
coverage/
EOF
	fi
	log_success ".gitignore updated"
}

setup_git_remote() {
	if [[ -n "$AZURE_DEVOPS_URL" ]]; then
		log_info "Configuring Azure DevOps remote..."
		
		# Check if origin already exists
		if git remote get-url origin &> /dev/null; then
			log_info "Remote 'origin' already exists, updating URL..."
			git remote set-url origin "$AZURE_DEVOPS_URL"
		else
			git remote add origin "$AZURE_DEVOPS_URL"
		fi
		
		log_success "Azure DevOps remote configured: $AZURE_DEVOPS_URL"
	fi
}

install_dependencies() {
	log_info "Installing dependencies with pnpm..."
	pnpm install
	log_success "Dependencies installed"
}

create_initial_commit() {
	log_info "Creating initial commit..."
	git add -A
	git commit -m "chore: initialize Finma Design System monorepo

- Configure Turbo with build caching and task pipelines
- Set up pnpm workspaces with catalog versions
- Add shared configuration packages (ESLint, Prettier, TypeScript)
- Create React component package structure
- Configure design token system with Styled Dictionary
- Set up Storybook documentation app
- Configure Vercel deployment
- Add Shadcn registry structure for component distribution"
	log_success "Initial commit created"
}

print_summary() {
	echo ""
	echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
	echo -e "${GREEN}║              Setup Complete! 🎉                               ║${NC}"
	echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
	echo ""
	echo "Project: ${PROJECT_NAME}"
	echo "Organization: ${ORGANIZATION_NAME}"
	echo "Node.js: v${NODE_EXACT_VERSION}"
	echo "pnpm: v${PNPM_VERSION}"
	echo "Registry: https://${REGISTRY_DOMAIN}"
	echo ""
	echo -e "${BLUE}Next steps:${NC}"
	echo "  1. Copy .env.example to .env.local and configure"
	echo "  2. Run 'pnpm dev' to start development servers"
	echo "  3. Visit http://localhost:6006 for Storybook"
	echo "  4. Visit http://localhost:3000 for the playground app"
	echo ""
	echo -e "${BLUE}Useful commands:${NC}"
	echo "  pnpm dev          Start all development servers"
	echo "  pnpm build        Build all packages and apps"
	echo "  pnpm lint         Lint all packages"
	echo "  pnpm test         Run all tests"
	echo "  pnpm format       Format all files"
	echo ""
}

main() {
	print_banner
	parse_arguments "$@"
	prompt_registry_domain
	
	echo ""
	log_info "Starting setup for project: ${PROJECT_NAME}"
	echo ""
	
	check_nvm
	setup_nodejs
	setup_pnpm
	
	create_directory_structure
	create_nvmrc
	create_editorconfig
	create_root_package_json
	create_pnpm_workspace
	create_turbo_json
	create_tsconfig_base
	create_tsconfig_root
	create_eslint_config
	create_prettier_config
	create_prettier_ignore
	create_env_example
	create_vercel_json
	create_gitignore_update
	
	setup_git_remote
	
	# Note: Dependencies installation and commit are commented out
	# as this script is meant to scaffold structure, not fully initialize
	# install_dependencies
	# create_initial_commit
	
	print_summary
}

# Run main function with all arguments
main "$@"
