import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { fileURLToPath } from "node:url";
import { loadEnv } from "vite";
import { defineConfig } from "vitest/config";

// Paths owned by the backend. In development Vite proxies them to the backend stack so
// the SPA and the API share one origin (no CORS, relative `/api/...` calls), exactly
// like the nginx edge in Compose and the Ingress in Kubernetes.
// Keep in sync with backend/config/urls.py and ops/nginx/*.conf.
const BACKEND_PREFIXES = ["api", "admin", "rosetta", "__debug__", "healthz", "readyz"];
const LANGUAGES = ["en", "ru"];
const backendPaths = `^/((${LANGUAGES.join("|")})/)?(${BACKEND_PREFIXES.join("|")})(/|$)`;

export default defineConfig(({ mode }) => {
  // VITE_PORT / VITE_PROXY_TARGET from .env.local (see .env.example); never bundled.
  const env = loadEnv(mode, process.cwd(), "");

  return {
    plugins: [react(), tailwindcss()],
    resolve: {
      // `@/` = src/. Must match "paths" in tsconfig.app.json; Vitest inherits it from here.
      alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) },
    },
    server: {
      port: Number(env.VITE_PORT) || 5173,
      strictPort: true,
      // Listen on all interfaces: the Compose dev edge (nginx in a container) reaches
      // this server through host.docker.internal, which cannot see a localhost-only bind.
      host: true,
      proxy: {
        [backendPaths]: {
          target: env.VITE_PROXY_TARGET || "http://localhost:8050",
          // Keep the browser's Host header: it is in the backend's ALLOWED_HOSTS/CSRF
          // trusted origins (localhost), so admin login through the proxy works.
          changeOrigin: false,
        },
      },
    },
    test: {
      environment: "jsdom",
      setupFiles: ["./src/test/setup.ts"],
    },
  };
});
