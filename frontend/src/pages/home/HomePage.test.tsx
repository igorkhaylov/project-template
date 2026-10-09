import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";

import { HomePage } from "./HomePage";

const meta = {
  name: "ProjectTemplate",
  version: "sha-abc123",
  environment: "test",
  languages: [{ code: "en", name: "English" }],
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

describe("HomePage", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("renders backend metadata from /api/v1/meta/", async () => {
    const fetchMock = vi.fn(async () => jsonResponse(meta));
    vi.stubGlobal("fetch", fetchMock);

    render(<HomePage />);

    expect(await screen.findByText("ProjectTemplate")).toBeInTheDocument();
    expect(screen.getByText("sha-abc123")).toBeInTheDocument();
    expect(screen.getByText("en (English)")).toBeInTheDocument();
    const [request] = fetchMock.mock.calls[0] as unknown as [Request];
    expect(new URL(request.url).pathname).toBe("/api/v1/meta/");
  });

  it("reports an unreachable API", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response("down", { status: 503 })),
    );

    render(<HomePage />);

    expect(await screen.findByRole("alert")).toHaveTextContent("HTTP 503");
  });

  it("re-requests the metadata when the user clicks Refresh", async () => {
    const user = userEvent.setup();
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(new Response("down", { status: 503 }))
      .mockResolvedValueOnce(jsonResponse(meta));
    vi.stubGlobal("fetch", fetchMock);

    render(<HomePage />);
    expect(await screen.findByRole("alert")).toHaveTextContent("HTTP 503");

    await user.click(screen.getByRole("button", { name: "Refresh" }));

    expect(await screen.findByText("sha-abc123")).toBeInTheDocument();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });
});
