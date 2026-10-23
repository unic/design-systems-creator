# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Bash-based monorepo generator** for creating design systems. It scaffolds complete TypeScript monorepos with Turborepo, pnpm workspaces, React component libraries, Style Dictionary design tokens, and Storybook.

**License**: LGPL-3.0-or-later

## Running the Generator

```sh
# Main entry point — creates a full design system monorepo
./bin/monorepo-init.sh --project-name my-design-system --organization my-org

# Alternative monolithic script (older pattern)
./bin/setup-monorepo.sh

# Helper for adding deps to generated monorepos
./bin/add-dependency.sh
```

**Prerequisites**: pnpm, yq, jq, Node.js LTS

## Checks

```sh
pnpm lint   # shellcheck + shfmt on bin/, lib/ and tests/
pnpm test   # generates @repo/design-tokens and checks CSS output for tests/fixtures/design-tokens/ (needs network for `pnpm add`)
```

## Architecture

The generator is organized as a modular Bash library:

- **`bin/monorepo-init.sh`** — Main orchestrator. Sources all `lib/` modules and runs them in sequence.
- **`bin/setup-monorepo.sh`** — Older monolithic version of the same flow.
- **`lib/utils.sh`** — Logging, argument parsing, shared helpers.
- **`lib/prerequisites.sh`** — Validates required tools (pnpm, yq, jq, Node).
- **`lib/repository.sh`** — Turbo repo init via `pnpm dlx create-turbo@latest`, workspace setup, renames `@repo/ui` → `@repo/ui-react`.
- **`lib/configuration.sh`** — Root config files (eslint, prettier, editorconfig, tsconfig, .npmrc).
- **`lib/package-prettier.sh`** — Creates `@repo/prettier-config` shared package.
- **`lib/package-design-tokens.sh`** — Creates `@repo/design-tokens`: single-file Tokens Studio exports (DTCG or legacy, one format per build) are split per set, then built per brand with Style Dictionary and `@tokens-studio/sd-transforms`, configured in `token-config.js`.
- **`lib/package-storybook.sh`** — Creates `apps/storybook-react` via Storybook CLI.
- **`lib/dependencies.sh`** — Populates pnpm catalog, standardizes all `package.json` files.
- **`lib/finalization.sh`** — Vercel deployment config, VS Code settings, final `pnpm install`.

### Generator Execution Flow

1. Parse args → check prerequisites
2. Create Turbo monorepo skeleton
3. Set up workspace config with pnpm catalog and security policies
4. Generate shared config packages (eslint, prettier, typescript)
5. Generate design tokens package (Tokens Studio + Style Dictionary)
6. Initialize Storybook app
7. Populate pnpm catalog with pinned latest versions
8. Standardize all package.json files
9. Create deployment/VS Code/editor configs
10. Run `pnpm install`

### Generated Monorepo Structure

```text
apps/
  web/                  # Next.js website
  storybook-react/      # Storybook documentation
packages/
  config/{eslint,prettier,typescript}/
  design-tokens/        # Tokens Studio + Style Dictionary
  ui-react/             # React component library
registry/               # Shadcn registry (tokens, react, utilities)
```

## Key Design Decisions

- **pnpm catalog** centralizes all dependency versions in `pnpm-workspace.yaml` rather than per-package
- **Security policies**: trust downgrade detection, minimum release age, strict lifecycle builds
- **Tabs** for code indentation, spaces for JSON/YAML (configured via `.editorconfig`)
- **DTCG format** for the sample design tokens (W3C Design Token Community Group standard); legacy Tokens Studio exports also build

## Shell Script Conventions

- All scripts use `#!/usr/bin/env bash` with `set -euo pipefail`
- Library files are sourced (not executed) by the main script
- Functions use `log_info`, `log_success`, `log_warning`, `log_error` from `lib/utils.sh`
- Heavy use of heredocs for generating config files
- `yq` for YAML manipulation, `jq` for JSON manipulation
