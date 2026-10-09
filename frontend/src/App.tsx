import { useEffect, useState } from "react";

import { api } from "./api/client";
import type { components } from "./api/schema";
import { appVersion, config } from "./config";

type Meta = components["schemas"]["Meta"];

type State =
  | { status: "loading" }
  | { status: "ok"; meta: Meta }
  | { status: "error"; message: string };

/**
 * Starter screen: proves the whole chain works end to end — runtime config, the typed
 * API client, the backend contract — and shows which builds are talking to each other.
 * Replace it with the real app; keep the pattern (typed calls via `api`).
 */
export default function App() {
  const [state, setState] = useState<State>({ status: "loading" });

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
        if (!cancelled) setState({ status: "error", message: err instanceof Error ? err.message : String(err) });
      });
    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <main className="card">
      <h1>{state.status === "ok" ? state.meta.name : "ProjectTemplate"}</h1>
      <p className="muted">
        frontend {appVersion} · runtime {config.environment}
      </p>

      {state.status === "loading" && <p>Connecting to the API…</p>}

      {state.status === "error" && (
        <p className="status-error" role="alert">
          API unreachable: {state.message}
        </p>
      )}

      {state.status === "ok" && (
        <dl>
          <dt>Backend</dt>
          <dd className="status-ok">connected</dd>
          <dt>Version</dt>
          <dd>{state.meta.version}</dd>
          <dt>Environment</dt>
          <dd>{state.meta.environment}</dd>
          <dt>Languages</dt>
          <dd>{state.meta.languages.map((l) => `${l.code} (${l.name})`).join(", ")}</dd>
        </dl>
      )}
    </main>
  );
}
