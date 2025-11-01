import { defineConfig } from 'vitepress'
import { fileURLToPath } from 'url'
import { dirname, join } from 'path'
import { withSidebar } from 'vitepress-sidebar'

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

const vitePressOptions = {
  // Site appearance
  appearance: 'dark',
  
  // Favicon
  head: [
    ['link', { rel: 'icon', href: '/assets/logo_web.png' }],
    ['link', { rel: 'apple-touch-icon', href: '/assets/logo_web.png', sizes: '180x180' }],
    ['link', { rel: 'mask-icon', href: '/assets/logo_only.svg', color: '#ffffff' }],
    ['meta', { name: 'theme-color', content: '#ffffff' }],
    ['link', { rel: 'stylesheet', href: '/theme/custom.css' }]
  ],
  
  // Site metadata
  title: 'BurgInfra',
  description: 'Infrastructure documentation for BurgDev',
  
  // Vite configuration
  vite: {
    server: {
      host: true,
      port: 3036
    }
  },
  
  // Theme configuration
  themeConfig: {
    logo: '/assets/logo_web.png',
    
    // UI text
    outlineTitle: 'On this page',
    lastUpdatedText: 'Last updated',
    darkModeSwitchLabel: 'Theme',
    sidebarMenuLabel: 'Menu',
    returnToTopLabel: 'Return to top',
    langMenuLabel: 'Change language',
    editLink: {
      pattern: 'https://github.com/burgdev/burginfra/edit/main/docs/:path',
      text: 'Edit this page'
    },
    docFooter: {
      prev: 'Previous page',
      next: 'Next page'
    },

    // Navigation bar
    nav: [
      { text: 'Home', link: '/' },
      { text: 'Services',
        items: [
          { text: 'pix.crux.li', link: '/Services/pix.crux.li' },
          { text: 'wodo.re', link: '/Services/wodo.re' },
        ]
      },
      { text: 'Documentation',
        items: [
          { text: 'Applications', link: '/Applications/' },
          { text: 'Infrastructure', items: [
            { text: 'Linux', link: '/Infrastructure/Linux/' },
            { text: 'Docker', link: '/Infrastructure/Docker/' },
            { text: 'Kubernetes', link: '/Infrastructure/Kubernetes/' },
          ] },
          { text: 'Scripts', link: '/Scripts/' }
        ]
      },
      {
        text: 'Links',
        items: [
          { text: 'GitHub', link: 'https://github.com/burgdev/burginfra' },
        ]
      }
    ],
    
    outline: [2,4],

    // Social links
    socialLinks: [
      { icon: 'github', link: 'https://github.com/burgdev/burginfra' }
    ],

    // Footer
    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Copyright 2025-present <a href="https://burgdev.ch">BurgDev</a>'
    },

    // Search
    search: {
      provider: 'local',
      options: {
        translations: {
          button: {
            buttonText: 'Search',
            buttonAriaLabel: 'Search documentation'
          },
          modal: {
            noResultsText: 'No results for',
            resetButtonTitle: 'Reset search',
            footer: {
              selectText: 'to select',
              navigateText: 'to navigate',
              closeText: 'to close'
            }
          }
        }
      }
    }
  },

  // Markdown settings
  markdown: {
    lineNumbers: true
  }
}
const vitePressSidebarOptions = {
  // VitePress Sidebar's options here...
  documentRootPath: '/docs',
  collapsed: true,
  collapseDepth: 2,
  capitalizeFirst: false,
  excludeByGlobPattern: ['README.md'],
  useTitleFromFrontmatter: true,
  sortMenusByFrontmatterOrder: true,
  frontmatterOrderDefaultValue: 100,
  excludeFilesByFrontmatterFieldName: 'exclude',
  excludeByFolderDepth: 6,
  manualSortFileNameByPriority: ["index.md", "overview.md", "setup.md"],
  includeFolderIndexFile: true
};

export default defineConfig(withSidebar(vitePressOptions, vitePressSidebarOptions))
