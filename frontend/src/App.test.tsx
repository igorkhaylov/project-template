import { render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import App from "./App";

const meta = {
  name: "ProjectTemplate",
  version: "sha-abc123",
  environment: "test",
  languages: [{ code: "en", name: "English" }],
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

describe("App", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("renders backend metadata from /api/v1/meta/", async () => {
    const fetchMock = vi.fn(async () => jsonResponse(meta));
    vi.stubGlobal("fetch", fetchMock);

    render(<App />);

    expect(await screen.findByText("ProjectTemplate")).toBeInTheDocument();
    expect(screen.getByText("sha-abc123")).toBeInTheDocument();
    expect(screen.getByText("en (English)")).toBeInTheDocument();
    const [request] = fetchMock.mock.calls[0] as unknown as [Request];
    expect(new URL(request.url).pathname).toBe("/api/v1/meta/");
  });

  it("reports an unreachable API", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response("down", { status: 503 })));

    render(<App />);

    expect(await screen.findByRole("alert")).toHaveTextContent("HTTP 503");
  });
});
