/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** Build identity injected by CI (`--build-arg VITE_APP_VERSION=sha-…`); "dev" locally. */
  readonly VITE_APP_VERSION?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
