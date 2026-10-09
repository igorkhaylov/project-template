# Frontend architecture

Layered structure in the spirit of [Feature-Sliced Design](https://feature-sliced.design):
code is grouped by *what it is for*, and dependencies point one way only. Only the layers
that have real modules exist; the rest are described here so they land in the right
place when the time comes.

## Layers

| Layer | Holds | Exists today |
|---|---|---|
| `app/` | assembly and global setup: root component, error boundary, global styles; later providers, the router, i18n init | yes |
| `pages/` | one folder per route; composes widgets, features and entities into a screen | yes (`home`) |
| `widgets/` | large self-contained UI blocks reused across pages (header, sidebar, a table with its toolbar) | not yet |
| `features/` | one user action each (sign in, add to cart, switch language): UI plus the logic behind it | not yet |
| `entities/` | domain models (user, order): types, API bindings, small presentational pieces | not yet |
| `shared/` | project-agnostic code: API client, runtime config, utilities, the UI kit | yes |

Create a layer when its first real module appears. An empty folder is noise, and a
layer invented ahead of time tends to attract code that belongs elsewhere.

## The dependency rule

A module may import only from layers **below** its own:

```
app → pages → widgets → features → entities → shared
```

- `shared/` imports nothing above itself. If something in `shared` needs domain
  knowledge, it belongs in `entities`.
- Siblings inside one layer (`pages/a` ↔ `pages/b`, `features/x` ↔ `features/y`) do not
  import each other; lift the common part to a lower layer.
- Cross-layer imports use the `@/` alias (`@/shared/ui/button/Button`); imports inside a
  slice are relative (`./HomePage`). ESLint enforces the direction for `@/` paths
  (`no-restricted-imports` per layer in `eslint.config.js`), which is why cross-layer
  imports must go through the alias and not through `../../`.
- No cyclic imports. If two modules need each other, one of them is in the wrong layer.

`@/` maps to `src/` in two places that must agree: `paths` in `tsconfig.app.json` and
`resolve.alias` in `vite.config.ts` (Vitest inherits the latter).

## Current layout

```
src/
  main.tsx                     bootstrap: StrictMode + <App />
  app/
    App.tsx                    root composition (error boundary → page); providers go here
    ErrorBoundary.tsx          render-error fallback with a reload action
    styles.css                 Tailwind entry (`@import "tailwindcss"`) + base styles
  pages/
    home/
      HomePage.tsx             starter screen; replace it with the real first page
      HomePage.test.tsx
  shared/
    api/client.ts              THE typed API client; route every call through it
    api/schema.d.ts            GENERATED from api/openapi.yaml (npm run api:types); never edited
    config/appConfig.ts        runtime config (window.__APP_CONFIG__) + build version
    lib/cn.ts                  clsx + tailwind-merge
    ui/button/Button.tsx       first UI-kit component; siblings get their own folder
  test/setup.ts                jest-dom matchers, cleanup between tests
```

## Naming

| What | Convention | Example |
|---|---|---|
| folders | kebab-case | `shared/ui/button/`, `pages/order-details/` |
| components and types | PascalCase; the file is named after the component | `Button.tsx`, `HomePage.tsx` |
| hooks | `useSomething` | `useMeta.ts` |
| other TS files | camelCase | `appConfig.ts`, `cn.ts` |
| constants | UPPER_SNAKE_CASE | `DOCS_LINKS` |
| props | `<Component>Props` | `ButtonProps` |
| hand-written API transport types | `DTO` suffix (generated ones come from `schema.d.ts` as they are) | `OrderDTO` |
| tests | next to the module | `Button.test.tsx` |

Components stay small and split by responsibility, not by line count. No `any` and no
`@ts-ignore` / `eslint-disable` to get past an error: data from outside (API, storage,
URL) is `unknown` until it is narrowed.

## Adding libraries

Beyond React, Tailwind and the typed API client nothing is preinstalled. Add what the
project needs, where it belongs:

| Need | Library | Where it lives |
|---|---|---|
| routing | `react-router` | `app/router.tsx` builds the tree; `pages/*` are its targets |
| server state (cache, refetch, pagination) | `@tanstack/react-query`, plus `openapi-react-query` to keep calls typed | provider in `app/`; hooks in `entities/*/api` or `features/*/api` |
| forms and validation | `react-hook-form` + `zod` | per feature; schemas shared across features go to `entities` |
| client state shared between pages | `zustand` | a store per feature or entity; never in `shared` |
| i18n | `react-i18next` | init in `app/`; one namespace per feature |
| dates | `date-fns` or `dayjs` | thin wrappers in `shared/lib` |

A `useEffect` + `useState` fetch, as in `HomePage.tsx`, is fine for one or two calls.
Once calls need caching, deduplication or background refresh, add React Query instead
of growing the hand-rolled version.

## Working with the API

- Call the backend only through `shared/api/client.ts`. Its types come from
  `api/openapi.yaml`; a breaking backend change fails `npm run typecheck`, not production.
- **An error is not an empty result.** `api.GET` returns `{ data, error, response }`.
  `data === undefined` with a 4xx/5xx status is a failure to show; an empty array is a
  success to render. Never collapse the two into "nothing to display".
- **Query keys include everything the response depends on**:
  `["orders", { page, status, search }]`, not `["orders"]`, otherwise a filter change
  shows stale data.
- **The auth scheme is chosen with the backend**: session cookies (same origin, CSRF
  header) or a bearer token (kept in memory, refreshed on 401). Decide before the first
  authenticated endpoint and implement it once, in `shared/api`.
