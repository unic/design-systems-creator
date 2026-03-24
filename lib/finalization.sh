# shellcheck shell=bash
create_vercel_json() {
	log_info "Creating vercel.json..."
	cd "$TARGET_FOLDER" || exit

	cat >vercel.json <<'EOF'
{
  "$schema": "https://openapi.vercel.sh/vercel.json",
  "buildCommand": "pnpm install --frozen-lockfile && pnpm turbo run build --filter=web --filter=storybook-react",
  "installCommand": "pnpm install --frozen-lockfile",
  "framework": null,
  "ignoreCommand": "npx turbo-ignore",
  "env": {
    "NODE_ENV": "production"
  }
}
EOF

	log_success "vercel.json created"
}

copy_helper_scripts() {
	log_info "Copying helper scripts..."

	cd "$TARGET_FOLDER" || exit
	mkdir -p scripts

	if [ -f "$SCRIPT_DIR/add-dependency.sh" ]; then
		cp "$SCRIPT_DIR/add-dependency.sh" "$TARGET_FOLDER/scripts/add-dependency.sh"
		chmod +x "$TARGET_FOLDER/scripts/add-dependency.sh"
		log_success "Helper scripts copied to scripts/"
	else
		log_warning "add-dependency.sh not found in $SCRIPT_DIR"
	fi
}

setup_vscode() {
	log_info "Setting up VSCode..."
	cd "$TARGET_FOLDER" || exit

	mkdir -p .vscode
	cat >.vscode/settings.json <<'EOF'
{
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "files.eol": "\n",
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,
  "eslint.validate": [
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact",
    "vue",
    "html",
    "markdown",
    "json"
  ],
  "eslint.workingDirectories": [{ "mode": "auto" }],
  "prettier.requireConfig": true,
}
EOF

	cat >.vscode/extensions.json <<'EOF'
{
  "recommendations": [
    "editorconfig.editorconfig",
    "nucllear.vscode-extension-auto-import",
    "vivaxy.vscode-conventional-commits",
    "mikestead.dotenv",
    "dbaeumer.vscode-eslint",
    "vector-of-bool.gitflow",
    "eamodio.gitlens",
    "bradlc.vscode-tailwindcss",
    "vercel.turbo-vsc"
  ]
}
EOF

	log_success "VSCode configured"
}

document_dependency_management() {
	log_info "Documenting dependency management approach in README.md..."
	cd "$TARGET_FOLDER" || exit

	cat >>README.md <<'EOF'

---

## Dependency Management

This monorepo uses **pnpm workspaces** with a **centralized catalog** for dependency version management.

### Approach: Pure Catalog

All dependency versions are defined centrally in `pnpm-workspace.yaml` under the `catalog:` section. Individual packages reference these versions using the `catalog:` protocol instead of hardcoding version numbers.

**Why this approach?**

- **Single source of truth** — All versions defined in one place
- **Consistent versions** — Every package uses the same version of shared dependencies
- **Easier upgrades** — Change a version once, applies everywhere
- **Smaller lockfiles** — pnpm deduplicates more effectively
- **Clean root** — Root `package.json` only contains repository tooling

### Alternative Approaches (Not Used)

| Approach | Description | Trade-offs |
|----------|-------------|------------|
| **Pragmatic Catalog** | Uses `pnpm add --save-catalog -w` which populates catalog AND root | Pollutes root with non-tooling deps |
| **No Catalog** | Each package manages its own versions | Version drift, harder upgrades |
| **Hoisted** | All deps at root, packages inherit | Implicit dependencies, harder to isolate |

### Recommended Project Structure

```
monorepo/
├── package.json              # turbo, prettier, eslint only (repo tooling)
├── pnpm-workspace.yaml       # catalog: all versions defined here
│
├── packages/
│   ├── design-tokens/        # Design tokens (Style Dictionary + DTCG)
│   │   ├── tokens/           # Token source files (from Tokens Studio)
│   │   ├── sd.config.js      # Style Dictionary configuration
│   │   └── package.json      # devDeps: style-dictionary, typescript (catalog:)
│   │
│   ├── tailwind-config/      # Shared Tailwind + PostCSS configuration
│   │   ├── tailwind.config.js
│   │   ├── postcss.config.js
│   │   ├── shared-styles.css
│   │   └── package.json      # deps: design-tokens (workspace:)
│   │
│   ├── ui-react/             # React components
│   │   └── package.json      # peerDeps: react (catalog:)
│   │                         # deps: design-tokens (workspace:), clsx (catalog:)
│   │
│   ├── ui-vue/               # Vue components (future)
│   │   └── package.json      # peerDeps: vue (catalog:)
│   │
│   ├── ui-astro/             # Astro components (future)
│   │   └── package.json      # peerDeps: astro (catalog:)
│   │
│   └── config/               # Shared configs (eslint, tsconfig, etc.)
│
└── apps/
    ├── website/              # deps: ui-react (workspace:), tailwind-config (workspace:)
    ├── storybook-react/      # Storybook for React components and docs
    │   ├── .storybook/       # Storybook configuration
    │   ├── stories/          # Documentation and example stories
    │   └── vitest.config.ts  # Vitest integration for testing
    ├── storybook-vue/        # Storybook for Vue components (future)
    └── storybook-astro/      # Storybook for Astro components (future)
```

### Key Principles

| Concern | Where to Define |
|---------|-----------------|
| Version numbers | `pnpm-workspace.yaml` catalog |
| Framework runtime (react, vue) | Package's `peerDependencies` |
| Shared utilities (clsx, lodash) | Package's `dependencies` |
| Build tools (typescript, tsup) | Package's `devDependencies` |
| Repo orchestration (turbo) | Root `devDependencies` |
| Internal packages | `workspace:*` protocol |

### Adding Dependencies

Use the helper script to ensure dependencies are added correctly:

```bash
# Interactive mode
./scripts/add-dependency.sh

# With arguments
./scripts/add-dependency.sh --package react --to packages/ui-react --type peer
./scripts/add-dependency.sh --package typescript --to packages/tokens --dev
```

The script will:
1. Check if the package exists in the catalog
2. Prompt to add to catalog if missing (with latest version)
3. Add to the target package using `catalog:` protocol
4. Always use exact versions

### Manual Dependency Management

If you prefer manual management:

1. **Add to catalog** (in `pnpm-workspace.yaml`):
   ```yaml
   catalog:
     react: 19.0.0
   ```

2. **Add to package** (in the package directory):
   ```bash
   pnpm add --save-exact react@catalog:
   # or for devDependencies:
   pnpm add --save-exact -D typescript@catalog:
   # or for peerDependencies:
   pnpm add --save-exact --save-peer react@catalog:
   ```

EOF

	log_success "Dependency management documentation added to README.md"
}

install_dependencies() {
	log_info "Installing dependencies with pnpm..."
	cd "$TARGET_FOLDER" || exit

	# Clean up any existing node_modules and lockfile to ensure fresh install with exact versions
	log_info "Cleaning up existing node_modules and lockfile..."
	rm -rf node_modules pnpm-lock.yaml
	find . -type d -name "node_modules" -not -path "*/node_modules/*" -exec rm -rf {} + 2>/dev/null || true

	pnpm install

	log_success "Dependencies installed"
}

print_summary() {
	echo ""
	echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
	echo -e "${GREEN}║              Setup Complete! 🎉                               ║${NC}"
	echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
	echo ""
	echo "Project: ${PROJECT_NAME}"
	echo "Organization: ${ORGANIZATION_NAME}"
	echo "Node.js: $(node -v)"
	echo "pnpm: $(pnpm -v)"
	echo ""
	echo -e "${BLUE}Next steps:${NC}"
	echo "  1. Copy .env.example to .env.local and configure"
	echo "  2. Run 'pnpm dev' to start development servers"
	echo "  3. Visit http://localhost:6006 for Storybook React"
	echo "  4. Visit http://localhost:3000 for the web app"
	echo ""
	echo -e "${BLUE}Useful commands:${NC}"
	echo "  pnpm dev                  Start all development servers"
	echo "  pnpm build                Build all packages and apps"
	echo "  pnpm lint                 Lint all packages"
	echo "  pnpm test                 Run all tests"
	echo "  pnpm format               Format all files"
	echo ""
	echo -e "${BLUE}Storybook commands:${NC}"
	echo "  cd apps/storybook-react"
	echo "  pnpm dev                  Start Storybook dev server"
	echo "  pnpm test                 Run component tests with Vitest"
	echo "  pnpm test:ui              Run tests with Vitest UI"
	echo "  pnpm build                Build static Storybook"
	echo ""
	echo -e "${BLUE}Adding dependencies:${NC}"
	echo "  Use the helper script to add dependencies following best practices:"
	echo "  ./scripts/add-dependency.sh --help"
	echo ""
}
