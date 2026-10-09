import js from "@eslint/js";
import prettier from "eslint-config-prettier/flat";
import { defineConfig, globalIgnores } from "eslint/config";
import reactHooks from "eslint-plugin-react-hooks";
import reactRefresh from "eslint-plugin-react-refresh";
import globals from "globals";
import tseslint from "typescript-eslint";

// Layers, top to bottom. A module may import only from layers BELOW its own; `shared`
// imports nothing above itself. Enforced for `@/` imports (the convention for every
// cross-layer import). See docs/architecture.md.
const LAYERS = ["app", "pages", "widgets", "features", "entities", "shared"];

function forbidImportsFromLayersAbove(layer) {
  const above = LAYERS.slice(0, LAYERS.indexOf(layer));
  return {
    files: [`src/${layer}/**/*.{ts,tsx}`],
    rules: {
      "no-restricted-imports": [
        "error",
        {
          patterns: above.map((upper) => ({
            group: [`@/${upper}`, `@/${upper}/*`],
            message: `${layer} must not import from ${upper}: dependencies point downwards only (see docs/architecture.md).`,
          })),
        },
      ],
    },
  };
}

export default defineConfig([
  globalIgnores(["dist", "coverage", "src/shared/api/schema.d.ts"]),
  {
    files: ["**/*.{ts,tsx}"],
    extends: [
      js.configs.recommended,
      tseslint.configs.recommended,
      reactHooks.configs.flat.recommended,
      reactRefresh.configs.vite,
    ],
    languageOptions: {
      ecmaVersion: 2022,
      globals: globals.browser,
    },
  },
  ...LAYERS.slice(1).map(forbidImportsFromLayersAbove),
  // Last: turns off every formatting rule so Prettier is the only formatter.
  prettier,
]);
