import DefaultTheme from 'vitepress/theme'
import Layout from './Layout.vue'
import './custom.css'

// Import components
import K8sCommandsSnippet from "../snippets/k8s-commands.md";

export default {
  ...DefaultTheme,
  Layout,
  enhanceApp({ app }) {
    // Register global components
    app.component('K8sCommandsSnippet', K8sCommandsSnippet)
  }
}
