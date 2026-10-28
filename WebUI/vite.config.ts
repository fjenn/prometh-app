import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'node:path'
const swapped = new Set(['llm', 'prep', 'device', 'catalog', 'media', 'audio', 'blobs'])
export default defineConfig({
  base: './',
  plugins: [{ name: 'prometh-native', enforce: 'pre', resolveId(source, importer) {
    if (!importer || importer.includes('/src/native/')) return
    const match = source.match(/(?:^|\/)engine\/(\w+)(?:\.ts)?$/)
    if (match && swapped.has(match[1])) return path.resolve('src/native', match[1] + '.ts')
  } }, react()],
  build: { target: 'es2022', outDir: '../Sources/Prometh/Resources/WebUI', emptyOutDir: true },
})
