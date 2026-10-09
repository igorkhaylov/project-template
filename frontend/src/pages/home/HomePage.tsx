import { useEffect, useState } from "react";

import { api } from "@/shared/api/client";
import type { components } from "@/shared/api/schema";
import { appVersion, config } from "@/shared/config/appConfig";
import { Button } from "@/shared/ui/button/Button";

type Meta = components["schemas"]["Meta"];

type MetaState =
  { status: "loading" } | { status: "ok"; meta: Meta } | { status: "error"; message: string };

const DOCS_LINKS = [
  { label: "React", href: "https://react.dev" },
  { label: "Vite", href: "https://vite.dev" },
  { label: "Tailwind CSS", href: "https://tailwindcss.com/docs" },
] as const;

/**
 * Starter screen: proves the whole chain works end to end — runtime config, the typed
 * API client, the backend contract — and shows which builds are talking to each other.
 * Replace it with the real first page; keep the pattern (typed calls via `api`).
 */
export function HomePage() {
  const [state, setState] = useState<MetaState>({ status: "loading" });
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    let cancelled = false;
    api
      .GET("/api/v1/meta/")
      .then(({ data, response }) => {
        if (cancelled) return;
        if (data) setState({ status: "ok", meta: data });
        else setState({ status: "error", message: `HTTP ${response.status}` });
      })
      .catch((err: unknown) => {
        if (cancelled) return;
        setState({ status: "error", message: err instanceof Error ? err.message : String(err) });
      });
    return () => {
      cancelled = true;
    };
  }, [attempt]);

  function refresh() {
    setState({ status: "loading" });
    setAttempt((n) => n + 1);
  }

  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-md items-center p-4">
      <section className="w-full rounded-xl border border-gray-200 bg-white p-6 dark:border-gray-700 dark:bg-gray-800">
        <h1 className="text-2xl font-semibold">
          {state.status === "ok" ? state.meta.name : "ProjectTemplate"}
        </h1>
        <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">
          frontend {appVersion} · runtime {config.environment}
        </p>

        {state.status === "loading" && <p className="mt-4">Connecting to the API…</p>}

        {state.status === "error" && (
          <p role="alert" className="mt-4 text-red-600 dark:text-red-400">
            API unreachable: {state.message}
          </p>
        )}

        {state.status === "ok" && (
          <dl className="mt-4 grid grid-cols-[max-content_1fr] gap-x-4 gap-y-1.5 text-sm">
            <dt className="text-gray-500 dark:text-gray-400">Backend</dt>
            <dd className="font-mono text-emerald-600 dark:text-emerald-400">connected</dd>
            <dt className="text-gray-500 dark:text-gray-400">Version</dt>
            <dd className="font-mono">{state.meta.version}</dd>
            <dt className="text-gray-500 dark:text-gray-400">Environment</dt>
            <dd className="font-mono">{state.meta.environment}</dd>
            <dt className="text-gray-500 dark:text-gray-400">Languages</dt>
            <dd className="font-mono">
              {state.meta.languages.map((l) => `${l.code} (${l.name})`).join(", ")}
            </dd>
          </dl>
        )}

        <div className="mt-6 flex flex-wrap items-center justify-between gap-3">
          <Button onClick={refresh} disabled={state.status === "loading"}>
            Refresh
          </Button>
          <nav aria-label="Documentation" className="flex gap-3 text-sm">
            {DOCS_LINKS.map(({ label, href }) => (
              <a
                key={href}
                href={href}
                target="_blank"
                rel="noreferrer"
                className="rounded text-blue-600 underline-offset-2 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600 dark:text-blue-400"
              >
                {label}
              </a>
            ))}
          </nav>
        </div>
      </section>
    </main>
  );
}
