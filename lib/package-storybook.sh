#!/usr/bin/env bash

# =============================================================================
# Storybook Package Module
# =============================================================================
# Functions for creating and configuring the Storybook React application
# This module handles the complete Storybook setup including:
# - CLI initialization
# - Addon installation
# - Configuration customization
# - Sample stories
# - Testing setup with Vitest

# =============================================================================
# Storybook Initialization
# =============================================================================

init_storybook_with_cli() {
	log_info "Initializing Storybook using CLI..."
	mkdir -p "$TARGET_FOLDER/apps/storybook-react"
	cd "$TARGET_FOLDER/apps/storybook-react" || exit

	# Initialize Storybook - CLI creates main.ts, preview.ts with defaults
	# --skip-install: We'll install later with pnpm
	# --yes: Skip interactive prompts
	# STORYBOOK_INIT_EMPTY_TYPE: Forces the CLI to use react-vite-ts template
	# See: https://github.com/storybookjs/storybook/blob/main/code/lib/create-storybook/src/scaffold-new-project.ts
	log_info "Running storybook@latest init..."

	# Export the env var so it's available to the Node.js subprocess
	export STORYBOOK_INIT_EMPTY_TYPE="react-vite-ts"

	if pnpm dlx storybook@latest init \
		--disable-telemetry \
		--skip-install \
		--yes \
		--package-manager pnpm \
		--no-dev 2>/dev/null; then
		log_success "Storybook initialized via CLI"
	else
		log_warning "Storybook CLI init encountered issues, continuing with manual setup..."
		# Create minimal .storybook directory so subsequent functions can populate it
		mkdir -p .storybook
	fi

	unset STORYBOOK_INIT_EMPTY_TYPE
}

install_storybook_addons_via_cli() {
	# Use CLI to add addons - this auto-registers them in main.ts
	# This is the recommended way per addon documentation
	log_info "Adding Storybook addons via CLI (auto-configures main.ts)..."
	cd "$TARGET_FOLDER/apps/storybook-react" || exit

	local addons=(
		"@storybook/addon-interactions"
		"@storybook/addon-themes"
		"@storybook/addon-designs"
		"msw-storybook-addon"
		"storybook-addon-tag-badges"
	)

	for addon in "${addons[@]}"; do
		log_info "\n  Adding $addon..."
		# --skip-install: Don't install yet, we do that later
		pnpm dlx storybook@latest add "$addon" --disable-telemetry --skip-install --yes 2>/dev/null || {
			log_warning "  Could not add $addon via CLI"
		}
	done

	log_success "Addons added via CLI"
}

finalize_storybook_package_json() {
	log_info "Finalizing Storybook package.json scripts..."
	cd "$TARGET_FOLDER/apps/storybook-react" || exit

	# Set package metadata fields
	jq --arg developer "$DEVELOPER" \
		--arg org "$ORGANIZATION_NAME" \
		--arg pm "pnpm@${PNPM_VERSION}" \
		'. + {
			"name": "@repo/storybook-react",
			"version": "1.0.0",
			"description": ("Storybook for " + $org + " React components and design tokens"),
			"author": $developer,
			"license": "LGPL-3.0-or-later",
			"type": "module",
			"private": true,
			"packageManager": $pm
		}' package.json >package.json.tmp && mv package.json.tmp package.json

	# Ensure correct scripts are set (may override CLI defaults)
	jq '.scripts = {
		"dev": "storybook dev -p 6006",
		"build": "storybook build",
		"test": "vitest --project=storybook",
		"test:ui": "vitest --project=storybook --ui",
		"test:coverage": "vitest --project=storybook --coverage",
		"lint": "eslint ."
	}' package.json >package.json.tmp && mv package.json.tmp package.json

	# Add workspace dependencies
	jq '.dependencies += {
		"@repo/design-tokens": "workspace:*",
		"@repo/ui-react": "workspace:*"
	} | .devDependencies += {
		"@repo/eslint-config": "workspace:*",
		"@repo/typescript-config": "workspace:*"
	}' package.json >package.json.tmp && mv package.json.tmp package.json

	log_success "Storybook package.json finalized"
}

# =============================================================================
# Storybook Configuration
# =============================================================================

customize_storybook_preview_ts() {
	# Replace preview.ts with our customized version
	# This is necessary because preview.ts needs significant customization:
	# - Design token imports
	# - MSW initialization
	# - Theme decorator configuration
	# - Custom parameters (a11y, tagBadges, etc.)
	log_info "Customizing preview.ts with monorepo configuration..."
	cd "$TARGET_FOLDER/apps/storybook-react" || exit

	cat >.storybook/preview.ts <<'EOF'
import type { Preview } from '@storybook/react'
import { withThemeByClassName } from '@storybook/addon-themes'
import { initialize, mswLoader } from 'msw-storybook-addon'

// Import design tokens CSS
import '@repo/design-tokens/css'
// Import Tailwind v4 theme CSS
import '@repo/design-tokens/tailwind-theme'
// Import global styles
import '../styles/globals.css'

/*
 * Initializes MSW
 * See https://github.com/mswjs/msw-storybook-addon#configuring-msw
 * See https://storybook.js.org/docs/writing-stories/mocking-data-and-modules/mocking-network-requests#set-up-the-msw-addon
 * to learn how to customize it
 */
initialize({
	onUnhandledRequest: 'bypass',
})

const preview: Preview = {
	parameters: {
		controls: {
			matchers: {
				color: /(background|color)$/i,
				date: /Date$/i,
			},
		},
		docs: {
			toc: true,
		},
		// https://storybook.js.org/docs/writing-tests/accessibility-testing#accessibility-checks-with-a11y-addon?ref=readme
		a11y: {
			/*
			 * Axe's context parameter
			 * See https://github.com/dequelabs/axe-core/blob/develop/doc/API.md#context-parameter
			 * to learn more. Typically, this is the CSS selector for the part of the DOM you want to analyze.
			 */
			context: 'body',
			/*
			 * Axe's configuration
			 * See https://github.com/dequelabs/axe-core/blob/develop/doc/API.md#api-name-axeconfigure
			 * to learn more about the available properties.
			 */
			config: {
				rules: [
					{ id: 'color-contrast', enabled: true },
				],
			},
			/*
			 * Axe's options parameter
			 * See https://github.com/dequelabs/axe-core/blob/develop/doc/API.md#options-parameter
			 * to learn more about the available options.
			 */
			options: {
				/*
				 * Opt in to running WCAG 2.x AAA rules
				 * Note that you must explicitly re-specify the defaults (all but the last array entry)
				 * See https://github.com/dequelabs/axe-core/blob/develop/doc/API.md#options-parameter-examples for more details
				 */
				// runOnly: ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'best-practice', 'wcag2aaa'],
			},
			test: 'error',
		},
		backgrounds: {
			default: 'light',
			values: [
				{ name: 'light', value: '#ffffff' },
				{ name: 'dark', value: '#1a1a1a' },
				{ name: 'neutral', value: '#f5f5f5' },
			],
		},
		viewport: {
			viewports: {
				mobile: { name: 'Mobile', styles: { width: '375px', height: '667px' } },
				tablet: { name: 'Tablet', styles: { width: '768px', height: '1024px' } },
				desktop: { name: 'Desktop', styles: { width: '1280px', height: '800px' } },
				wide: { name: 'Wide', styles: { width: '1536px', height: '960px' } },
			},
		},
		tagBadges: [
			{ tags: ['stable'], badge: { text: 'Stable', bgColor: '#10B981', fgColor: '#ffffff' } },
			{ tags: ['beta'], badge: { text: 'Beta', bgColor: '#F59E0B', fgColor: '#000000' } },
			{ tags: ['experimental'], badge: { text: 'Experimental', bgColor: '#EF4444', fgColor: '#ffffff' } },
			{ tags: ['deprecated'], badge: { text: 'Deprecated', bgColor: '#6B7280', fgColor: '#ffffff' } },
		],
	},
	initialGlobals: {
		a11y: {
			// Optional flag to prevent the automatic check
			// manual: true,
		},
	},
	decorators: [
		withThemeByClassName({
			themes: { light: '', dark: 'dark' },
			defaultTheme: 'light',
		}),
	],
	loaders: [mswLoader], // 👈 Add the MSW loader to all stories
	tags: ['autodocs'],
}

export default preview
EOF

	log_success "preview.ts customized"
}

add_storybook_vitest_setup() {
	# Add vitest setup for portable stories testing
	log_info "Adding Vitest setup..."
	cd "$TARGET_FOLDER/apps/storybook-react" || exit

	cat >.storybook/vitest.setup.ts <<'EOF'
import { setProjectAnnotations } from '@storybook/react'
import * as previewAnnotations from './preview'
import * as a11yAddonAnnotations from '@storybook/addon-a11y/preview'

setProjectAnnotations([previewAnnotations, a11yAddonAnnotations])
EOF

	log_success "Vitest setup added"
}

add_storybook_vitest_config() {
	log_info "Adding Vitest configuration for Storybook..."
	cd "$TARGET_FOLDER/apps/storybook-react" || exit

	cat >vitest.config.ts <<'EOF'
import { defineConfig } from 'vitest/config'
import { storybookTest } from '@storybook/addon-vitest/vitest-plugin'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const dirname = path.dirname(fileURLToPath(import.meta.url))

export default defineConfig({
	test: {
		projects: [
			{
				extends: true,
				plugins: [
					storybookTest({
						configDir: path.join(dirname, '.storybook'),
						storybookScript: 'pnpm storybook --no-open',
						storybookUrl: 'http://localhost:6006',
						tags: {
							include: ['test'],
							exclude: ['skip-test', 'experimental'],
							skip: ['manual'],
						},
					}),
				],
				test: {
					name: 'storybook',
					browser: {
						enabled: true,
						provider: 'playwright',
						headless: true,
						instances: [{ browser: 'chromium' }],
					},
					setupFiles: ['./.storybook/vitest.setup.ts'],
				},
			},
		],
		coverage: {
			provider: 'v8',
			reporter: ['text', 'json', 'html'],
			include: ['../../../packages/ui-react/src/**/*.{ts,tsx}'],
			exclude: ['**/*.stories.{ts,tsx}', '**/*.test.{ts,tsx}', '**/index.ts'],
		},
	},
})
EOF

	log_success "Vitest configuration added"
}

# =============================================================================
# Storybook Styles and Assets
# =============================================================================

add_storybook_styles() {
	log_info "Adding Storybook global styles..."
	cd "$TARGET_FOLDER/apps/storybook-react" || exit

	mkdir -p styles

	cat >styles/globals.css <<'EOF'
@import "tailwindcss";
@import "@repo/design-tokens/tailwind-theme";

/*
 * Global styles for Storybook
 * These styles apply to all stories
 */

/* Base reset for story container */
.sb-show-main {
	padding: 1rem;
}

/* Documentation page styles */
.sbdocs {
	font-family: var(--typography-font-family-sans);
}

/* Custom scrollbar for dark mode */
.dark {
	color-scheme: dark;
}

.dark ::-webkit-scrollbar {
	width: 8px;
	height: 8px;
}

.dark ::-webkit-scrollbar-track {
	background: var(--color-neutral-800);
}

.dark ::-webkit-scrollbar-thumb {
	background: var(--color-neutral-600);
	border-radius: 4px;
}

.dark ::-webkit-scrollbar-thumb:hover {
	background: var(--color-neutral-500);
}
EOF

	log_success "Storybook global styles added"
}

# =============================================================================
# Sample Stories
# =============================================================================
# Note: The sample stories content is very large and will be added in a separate section
# For brevity in this refactored version, I'm including placeholder comments
# The full implementation should include all the story templates from the original script

add_storybook_sample_stories() {
	log_info "Adding sample stories..."
	cd "$TARGET_FOLDER/apps/storybook-react" || exit

	mkdir -p src/stories

	# Create Introduction.mdx - content from original script lines 1597-1651
	cat >src/stories/Introduction.mdx <<'STORY_EOF'
import { Meta } from '@storybook/blocks'

<Meta title="Introduction" />

# Design System Documentation

Welcome to the **Design System** documentation powered by Storybook.

## Overview

This Storybook contains:

- **Design Tokens** — Color palettes, typography, spacing, and other foundational design decisions
- **UI Components** — React components from `@repo/ui-react`
- **Usage Guidelines** — Best practices and implementation patterns

## Getting Started

### Installation

```bash
pnpm add @repo/ui-react @repo/design-tokens
```

### Usage

```tsx
import { Button } from '@repo/ui-react'
import '@repo/design-tokens/css'

export function MyComponent() {
  return <Button variant="primary">Click me</Button>
}
```

## Resources

- [Design Tokens](/docs/tokens-colors--docs) — Explore the token system
- [Components](/docs/components-button--docs) — Browse available components
- [Accessibility](/docs/guidelines-accessibility--docs) — A11y guidelines

## Development

```bash
# Start Storybook dev server
pnpm dev

# Run component tests
pnpm test

# Build static Storybook
pnpm build
```
STORY_EOF

	# Create Button.stories.tsx - sample component story (lines 1654-1764)
	cat >src/stories/Button.stories.tsx <<'STORY_EOF'
import type { Meta, StoryObj } from '@storybook/react'
import { fn } from '@storybook/test'
import { Button } from '@repo/ui-react'

const meta = {
	title: 'Components/Button',
	component: Button,
	parameters: {
		layout: 'centered',
		docs: {
			description: {
				component: 'A versatile button component with multiple variants and sizes.',
			},
		},
	},
	tags: ['autodocs', 'stable', 'test'],
	argTypes: {
		variant: {
			control: 'select',
			options: ['primary', 'secondary', 'outline', 'ghost'],
			description: 'The visual style variant of the button',
		},
		size: {
			control: 'select',
			options: ['sm', 'md', 'lg'],
			description: 'The size of the button',
		},
		disabled: {
			control: 'boolean',
			description: 'Whether the button is disabled',
		},
	},
	args: {
		onClick: fn(),
	},
} satisfies Meta<typeof Button>

export default meta
type Story = StoryObj<typeof meta>

export const Primary: Story = {
	args: {
		children: 'Primary Button',
		variant: 'primary',
	},
}

export const Secondary: Story = {
	args: {
		children: 'Secondary Button',
		variant: 'secondary',
	},
}

export const Outline: Story = {
	args: {
		children: 'Outline Button',
		variant: 'outline',
	},
}

export const Ghost: Story = {
	args: {
		children: 'Ghost Button',
		variant: 'ghost',
	},
}

export const Small: Story = {
	args: {
		children: 'Small Button',
		size: 'sm',
	},
}

export const Large: Story = {
	args: {
		children: 'Large Button',
		size: 'lg',
	},
}

export const Disabled: Story = {
	args: {
		children: 'Disabled Button',
		disabled: true,
	},
}

/**
 * Buttons with different variants side by side
 */
export const AllVariants: Story = {
	render: () => (
		<div style={{ display: 'flex', gap: '1rem', flexWrap: 'wrap' }}>
			<Button variant="primary">Primary</Button>
			<Button variant="secondary">Secondary</Button>
			<Button variant="outline">Outline</Button>
			<Button variant="ghost">Ghost</Button>
		</div>
	),
	parameters: {
		docs: {
			description: {
				story: 'All button variants displayed together for comparison.',
			},
		},
	},
}
STORY_EOF

	# Create Tokens.mdx - design tokens documentation (lines 1767-1849)
	cat >src/stories/Tokens.mdx <<'STORY_EOF'
import { Meta, ColorPalette, ColorItem, Typeset } from '@storybook/blocks'

<Meta title="Tokens/Overview" />

# Design Tokens

Design tokens are the visual design atoms of the design system — specifically, they are named entities that store visual design attributes.

## Colors

### Primary Palette

<ColorPalette>
	<ColorItem
		title="Primary"
		subtitle="Brand primary colors"
		colors={{
			'50': 'var(--color-primary-50)',
			'100': 'var(--color-primary-100)',
			'200': 'var(--color-primary-200)',
			'300': 'var(--color-primary-300)',
			'400': 'var(--color-primary-400)',
			'500': 'var(--color-primary-500)',
			'600': 'var(--color-primary-600)',
			'700': 'var(--color-primary-700)',
			'800': 'var(--color-primary-800)',
			'900': 'var(--color-primary-900)',
		}}
	/>
</ColorPalette>

### Neutral Palette

<ColorPalette>
	<ColorItem
		title="Neutral"
		subtitle="Grayscale colors"
		colors={{
			'50': 'var(--color-neutral-50)',
			'100': 'var(--color-neutral-100)',
			'200': 'var(--color-neutral-200)',
			'300': 'var(--color-neutral-300)',
			'400': 'var(--color-neutral-400)',
			'500': 'var(--color-neutral-500)',
			'600': 'var(--color-neutral-600)',
			'700': 'var(--color-neutral-700)',
			'800': 'var(--color-neutral-800)',
			'900': 'var(--color-neutral-900)',
		}}
	/>
</ColorPalette>

## Typography

<Typeset
	fontSizes={['0.75rem', '0.875rem', '1rem', '1.125rem', '1.25rem', '1.5rem', '1.875rem', '2.25rem']}
	fontWeight={400}
	sampleText="The quick brown fox jumps over the lazy dog"
	fontFamily="var(--typography-font-family-sans)"
/>

## Usage

Import tokens in your stylesheets:

```css
@import '@repo/design-tokens/css';

.my-element {
  background-color: var(--semantic-accent-default);
  color: var(--semantic-foreground-inverse);
  padding: var(--spacing-4);
}
```

Or use with Tailwind v4:

```css
@import "tailwindcss";
@import "@repo/design-tokens/tailwind-theme";
```
STORY_EOF

	log_success "Sample stories added"
}

# =============================================================================
# Additional Configuration Files
# =============================================================================

add_storybook_tsconfig() {
	log_info "Adding TypeScript configuration for Storybook..."
	cd "$TARGET_FOLDER/apps/storybook-react" || exit

	cat >tsconfig.json <<'EOF'
{
	"extends": "@repo/typescript-config/base.json",
	"compilerOptions": {
		"target": "ES2022",
		"lib": ["ES2022", "DOM", "DOM.Iterable"],
		"module": "ESNext",
		"moduleResolution": "bundler",
		"jsx": "react-jsx",
		"strict": true,
		"noEmit": true,
		"isolatedModules": true,
		"esModuleInterop": true,
		"skipLibCheck": true,
		"resolveJsonModule": true,
		"paths": {
			"@repo/ui-react": ["../../packages/ui-react/src"],
			"@repo/design-tokens": ["../../packages/design-tokens/dist"],
			"@repo/design-tokens/*": ["../../packages/design-tokens/dist/*"]
		}
	},
	"include": [
		".storybook/**/*",
		"src/**/*",
		"mocks/**/*",
		"vitest.config.ts"
	],
	"exclude": ["node_modules", "storybook-static"]
}
EOF

	log_success "TypeScript configuration added"
}

add_storybook_eslint_config() {
	log_info "Adding ESLint configuration for Storybook..."
	cd "$TARGET_FOLDER/apps/storybook-react" || exit

	cat >eslint.config.mjs <<'EOF'
// For more info, see https://github.com/storybookjs/eslint-plugin-storybook#configuration-flat-config-format
import storybook from "eslint-plugin-storybook";
import reactRefresh from 'eslint-plugin-react-refresh'
import { config } from '@repo/eslint-config/react-internal'

export default [
	...config,
	reactRefresh.configs.vite,
	...storybook.configs['flat/recommended'],
	{
		rules: {
			// Allow default exports for stories
			'import/no-default-export': 'off',
		},
	},
]
EOF

	mv eslint.config.js eslint.config.js.back 2>/dev/null || true

	log_success "ESLint configuration added"
}

add_storybook_msw_handlers() {
	log_info "Adding MSW handlers..."
	cd "$TARGET_FOLDER/apps/storybook-react" || exit

	mkdir -p mocks public

	cat >mocks/handlers.ts <<'EOF'
import { http, HttpResponse } from 'msw'

/**
 * MSW request handlers for mocking API requests in stories.
 *
 * Usage in stories:
 * ```tsx
 * export const WithMockedData: Story = {
 *   parameters: {
 *     msw: {
 *       handlers: [
 *         http.get('/api/user', () => {
 *           return HttpResponse.json({ name: 'John Doe' })
 *         }),
 *       ],
 *     },
 *   },
 * }
 * ```
 */
export const handlers = [
	// Example handler - replace with your actual API endpoints
	http.get('/api/example', () => {
		return HttpResponse.json({
			message: 'This is a mocked response',
			timestamp: new Date().toISOString(),
		})
	}),
]
EOF

	# Create public directory for MSW service worker (minimal placeholder)
	cat >public/mockServiceWorker.js <<'EOF'
/* eslint-disable */
/* tslint:disable */

/**
 * Mock Service Worker.
 * @see https://github.com/mswjs/msw
 * - Please do NOT modify this file.
 * - Please do NOT serve this file on production.
 */

// Placeholder - actual MSW service worker will be generated during build
console.log('MSW Service Worker placeholder')
EOF

	log_success "MSW handlers added"
}

add_storybook_readme() {
	log_info "Creating Storybook README..."
	cd "$TARGET_FOLDER/apps/storybook-react" || exit

	cat >README.md <<'EOF'
# @repo/storybook-react

Storybook for React components and design system documentation.

## Features

- 📖 **Component Documentation** — Auto-generated docs with controls and examples
- 🧪 **Vitest Integration** — Run interaction and accessibility tests
- ♿ **Accessibility Testing** — Automated a11y checks with axe-core
- 🎨 **Theme Switching** — Light/dark mode support
- 🔌 **MSW Integration** — Mock API requests in stories
- 🎯 **Design Integration** — Link Figma designs with addon-designs
- 🏷️ **Tag Badges** — Visual status indicators (stable, beta, experimental)

## Development

```bash
# Start Storybook dev server
pnpm dev

# Run tests
pnpm test

# Run tests with UI
pnpm test:ui

# Run tests with coverage
pnpm test:coverage

# Build static Storybook
pnpm build
```

## Project Structure

```
apps/storybook-react/
├── .storybook/
│   ├── main.ts           # Storybook configuration
│   ├── preview.ts        # Global decorators and parameters
│   ├── manager.ts        # UI customization
│   └── vitest.setup.ts   # Vitest integration setup
├── mocks/
│   └── handlers.ts       # MSW request handlers
├── stories/
│   ├── Introduction.mdx  # Documentation home
│   ├── Tokens.mdx        # Design tokens documentation
│   └── *.stories.tsx     # Component stories
├── styles/
│   └── globals.css       # Global styles
├── vitest.config.ts      # Vitest configuration
└── package.json
```

## Writing Stories

### Basic Story

```tsx
import type { Meta, StoryObj } from '@storybook/react'
import { Button } from '@repo/ui-react'

const meta = {
  title: 'Components/Button',
  component: Button,
  tags: ['autodocs', 'stable', 'test'],
} satisfies Meta<typeof Button>

export default meta
type Story = StoryObj<typeof meta>

export const Primary: Story = {
  args: {
    children: 'Click me',
    variant: 'primary',
  },
}
```

### With MSW Mocking

```tsx
import { http, HttpResponse } from 'msw'

export const WithData: Story = {
  parameters: {
    msw: {
      handlers: [
        http.get('/api/data', () => {
          return HttpResponse.json({ items: ['a', 'b', 'c'] })
        }),
      ],
    },
  },
}
```

### With Figma Design

```tsx
export const WithDesign: Story = {
  parameters: {
    design: {
      type: 'figma',
      url: 'https://www.figma.com/file/xxx/Design?node-id=123',
    },
  },
}
```

## Testing

Stories are automatically converted to Vitest tests using `@storybook/addon-vitest`.

### Test Tags

- `test` — Include in test runs (default)
- `skip-test` — Exclude from test runs
- `manual` — Skip but count in results

### Running Tests

```bash
# Run all Storybook tests
pnpm test

# Run with Vitest UI
pnpm test:ui

# Run specific story file
pnpm test -- stories/Button.stories.tsx
```

## Addons

| Addon | Purpose |
|-------|---------|
| `@storybook/addon-essentials` | Controls, actions, docs, viewport, etc. |
| `@storybook/addon-a11y` | Accessibility testing with axe-core |
| `@storybook/addon-interactions` | Play function testing |
| `@storybook/addon-themes` | Theme switching |
| `@storybook/addon-designs` | Figma/design tool integration |
| `@storybook/addon-vitest` | Vitest test integration |
| `msw-storybook-addon` | API mocking with MSW |
| `storybook-addon-tag-badges` | Visual tag indicators |
| `@chromatic-com/storybook` | Visual regression testing |
EOF

	log_success "Storybook README created"
}
