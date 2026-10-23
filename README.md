# design-systems-creator

Bash CLI that scaffolds a TypeScript monorepo for design systems — Turborepo, pnpm workspaces, React component library, Style Dictionary tokens, and Storybook.

## What it generates

```text
<project-name>/
├── apps/
│   ├── web/                  # Next.js website
│   └── storybook-react/      # Storybook documentation
├── packages/
│   ├── config/
│   │   ├── eslint/
│   │   ├── prettier/
│   │   └── typescript/
│   ├── design-tokens/        # Tokens Studio + Style Dictionary
│   └── ui-react/             # React component library
├── pnpm-workspace.yaml       # Centralized pnpm catalog
├── turbo.json
└── .vscode/
```

## Prerequisites
- Bash 4.2 or higher
- [pnpm](https://pnpm.io/) — package manager
- [yq](https://github.com/mikefarah/yq) — YAML processor
- [jq](https://jqlang.github.io/jq/) — JSON processor
- Node.js LTS

## Quick start

```sh
./bin/monorepo-init.sh --project-name my-design-system --organization my-org
```

This creates a `my-design-system/` directory in the current working directory (so, in this repo).

Alternatively you can go to the folder where you want the new project folder to be created and execute the initialisation:

```sh
./../../design-systems-creator/bin/monorepo-init.sh --project-name my-design-system --organization my-org
```

## CLI reference

### `bin/monorepo-init.sh`

Main entry point.

| Flag                  | Required | Description                                           |
| --------------------- | -------- | ----------------------------------------------------- |
| `--project-name NAME` | Yes      | Project name (used for directory and package scoping) |
| `--organization NAME` | Yes      | Organization name                                     |

### `add-dependency.sh`

Manages dependencies in a generated monorepo. Resolves versions against the pnpm catalog and adds entries automatically.

> **Note:** The generator copies this script to `scripts/add-dependency.sh` in the generated monorepo.
> The examples below use the path as it appears in a generated project.

**Interactive mode** (prompts for package, target, and type):

```sh
./scripts/add-dependency.sh
```

**Non-interactive mode:**

```sh
./scripts/add-dependency.sh --package react --to packages/ui-react --type peer
./scripts/add-dependency.sh -p typescript -t packages/tokens -D
```

| Flag             | Alias | Description                                    |
| ---------------- | ----- | ---------------------------------------------- |
| `--package NAME` | `-p`  | Package name to add                            |
| `--to PATH`      | `-t`  | Target package path (e.g. `packages/ui-react`) |
| `--type TYPE`    |       | `dep` (default), `dev`, or `peer`              |
| `--dev`          | `-D`  | Shorthand for `--type dev`                     |
| `--peer`         | `-P`  | Shorthand for `--type peer`                    |

## Development

```sh
pnpm run lint       # shellcheck + shfmt diff check
pnpm run format     # shfmt write
```

## License

[LGPL-3.0-or-later](./LICENSE)
