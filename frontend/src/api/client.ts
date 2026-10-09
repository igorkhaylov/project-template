import createClient from "openapi-fetch";

import { config } from "../config";
import type { paths } from "./schema";

/**
 * Typed HTTP client over the backend's OpenAPI contract.
 *
 * `paths` is generated from ../../api/openapi.yaml by `npm run api:types` (or
 * `make api-schema` from the repo root); a backend change that breaks a call fails
 * `npm run typecheck` here instead of failing in production.
 *
 * Relative base URL = same origin as the SPA; `window.location.origin` makes that
 * explicit so the client also works outside a browser (tests).
 */
export const api = createClient<paths>({
  baseUrl: config.apiBaseUrl || window.location.origin,
  // Resolve `fetch` per call rather than capturing it at import time, so a stubbed or
  // polyfilled global (tests, instrumentation) is honoured.
  fetch: (request) => globalThis.fetch(request),
});
