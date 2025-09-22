# BurgInfra Documentation

This directory contains the documentation for the BurgInfra project, built with [VitePress](https://vitepress.dev/).

## Getting Started

### Prerequisites

- Node.js 16 or higher
- npm or yarn

### Installation

1. Install dependencies:
   ```bash
   npm install
   ```

2. Start the development server:
   ```bash
   npm run docs:dev
   ```

3. Open your browser to:
   ```
   http://localhost:3036
   ```

## Adding New Documentation

1. Create a new Markdown file in the appropriate directory
2. Add the file to the navigation in `.vitepress/config.js` if needed
3. Use the following frontmatter at the top of your Markdown file:

```yaml
---
title: Page Title
order: 100
exclude: false
---
# Different Page Title (optional)
```

`order` and `exclude` are optional.

## Building for Production

```bash
# Build the static site
npm run docs:build

# Preview the production build
npm run docs:serve
```

The built files will be in `docs/.vitepress/dist`.

## License

MIT
