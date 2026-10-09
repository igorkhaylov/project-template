import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

import { Button } from "./Button";

describe("Button", () => {
  it("is a non-submitting button by default and merges Tailwind classes", () => {
    render(<Button className="px-8">Save</Button>);

    const button = screen.getByRole("button", { name: "Save" });
    expect(button).toHaveAttribute("type", "button");
    expect(button).toHaveClass("px-8");
    expect(button).not.toHaveClass("px-4");
  });

  it("calls onClick and respects disabled", async () => {
    const user = userEvent.setup();
    const onClick = vi.fn();
    render(
      <>
        <Button onClick={onClick}>Go</Button>
        <Button onClick={onClick} disabled>
          Stop
        </Button>
      </>,
    );

    await user.click(screen.getByRole("button", { name: "Go" }));
    await user.click(screen.getByRole("button", { name: "Stop" }));

    expect(onClick).toHaveBeenCalledTimes(1);
  });
});
