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
    ['meta', { name: 'theme-color', content: '#ffffff' }]
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
      { text: 'Documentation',
        items: [
          { text: 'Applications', link: '/apps/overview' },
          { text: 'Infrastructure', link: '/infrastructure' },
          { text: 'Scripts', link: '/scripts/' }
        ]
      },
      {
        text: 'Links',
        items: [
          { text: 'GitHub', link: 'https://github.com/burgdev/burginfra' },
        ]
      }
    ],

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
  capitalizeFirst: true,
  excludeByGlobPattern: ['README.md'],
  useTitleFromFrontmatter: true,
  sortMenusByFrontmatterOrder: true,
  frontmatterOrderDefaultValue: 100,
  excludeFilesByFrontmatterFieldName: 'exclude',
  excludeByFolderDepth: 6,
  manualSortFileNameByPriority: ["overview.md"]
};

export default defineConfig(withSidebar(vitePressOptions, vitePressSidebarOptions))

// Sidebar generators
function getInfrastructureSidebar() {
  return [
    {
      text: 'Infrastructure',
      items: [
        { text: 'Overview', link: '/infrastructure/' },
        { 
          text: 'Kubernetes',
          collapsed: true,
          items: [
            { text: 'Getting Started', link: '/infrastructure/kubernetes/' },
            { text: 'k3s Setup', link: '/infrastructure/kubernetes/k3s-setup' },
            { text: 'k9s Setup', link: '/infrastructure/kubernetes/k9s-setup' },
            { text: 'Applications', link: '/infrastructure/kubernetes/apps' }
          ]
        },
        { 
          text: 'Networking',
          link: '/infrastructure/networking/'
        }
      ]
    }
  ]
}

function getAppsSidebar() {
  return [
    {
      text: 'Applications',
      items: [
        { text: 'Overview', link: '/apps/' },
        // Add more applications here as needed
      ]
    }
  ]
}

function getScriptsSidebar() {
  return [
    {
      text: 'Scripts',
      items: [
        { text: 'Overview', link: '/scripts/' },
        // Add more script categories here as needed
      ]
    }
  ]
}
