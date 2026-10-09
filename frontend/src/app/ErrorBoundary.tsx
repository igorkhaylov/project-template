import { Component, type ErrorInfo, type ReactNode } from "react";

import { Button } from "@/shared/ui/button/Button";

interface ErrorBoundaryProps {
  children: ReactNode;
}

interface ErrorBoundaryState {
  error: Error | null;
}

/**
 * Last line of defence for render errors: shows what happened and lets the user reload
 * instead of a blank page. Errors are logged, never swallowed. Component-level
 * boundaries (per page or widget) can be added on top; this one stays at the root.
 */
export class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  state: ErrorBoundaryState = { error: null };

  static getDerivedStateFromError(error: unknown): ErrorBoundaryState {
    return { error: error instanceof Error ? error : new Error(String(error)) };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error("Unhandled render error", error, info.componentStack);
  }

  render() {
    if (this.state.error) {
      return (
        <main
          role="alert"
          className="mx-auto flex min-h-dvh w-full max-w-md flex-col items-start justify-center gap-4 p-4"
        >
          <h1 className="text-2xl font-semibold">Something went wrong</h1>
          <p className="font-mono text-sm text-red-600 dark:text-red-400">
            {this.state.error.message}
          </p>
          <Button onClick={() => window.location.reload()}>Reload page</Button>
        </main>
      );
    }
    return this.props.children;
  }
}
