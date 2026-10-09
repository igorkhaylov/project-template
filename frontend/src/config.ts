/**
 * Runtime configuration: values that differ per ENVIRONMENT but not per build.
 *
 * They come from `/config.js` (loaded in index.html before the bundle), which the Docker
 * image's nginx renders from `APP_*` environment variables at container start. The same
 * image therefore serves dev, stage and prod. Build-time `VITE_*` variables are reserved
 * for build identity (version), never for environment-specific values.
 */
export interface AppConfig {
  /** Prefix for API calls. Empty = same origin (the edge routes /api/ to the backend). */
  apiBaseUrl: string;
  /** dev | stage | prod — mirrors the backend's ENVIRONMENT. */
  environment: string;
}

declare global {
  interface Window {
    __APP_CONFIG__?: Partial<AppConfig>;
  }
}

const defaults: AppConfig = { apiBaseUrl: "", environment: "dev" };

export const config: AppConfig = { ...defaults, ...(window.__APP_CONFIG__ ?? {}) };

export const appVersion: string = import.meta.env.VITE_APP_VERSION || "dev";
