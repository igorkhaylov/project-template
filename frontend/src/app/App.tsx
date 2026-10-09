import { HomePage } from "@/pages/home/HomePage";

import { ErrorBoundary } from "./ErrorBoundary";

/**
 * Root composition. Global concerns live here (error boundary now; providers, the
 * router and i18n later); pages compose the rest. See docs/architecture.md.
 */
export function App() {
  return (
    <ErrorBoundary>
      <HomePage />
    </ErrorBoundary>
  );
}
