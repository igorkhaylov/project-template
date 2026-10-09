import type { ButtonHTMLAttributes } from "react";

import { cn } from "@/shared/lib/cn";

export type ButtonVariant = "primary" | "secondary";

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
}

const BASE_CLASSES =
  "inline-flex items-center justify-center rounded-lg px-4 py-2 text-sm font-medium transition-colors " +
  "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600 " +
  "disabled:cursor-not-allowed disabled:opacity-50";

const VARIANT_CLASSES: Record<ButtonVariant, string> = {
  primary: "bg-blue-600 text-white hover:bg-blue-700",
  secondary:
    "border border-gray-300 bg-white text-gray-900 hover:bg-gray-100 " +
    "dark:border-gray-600 dark:bg-gray-800 dark:text-gray-50 dark:hover:bg-gray-700",
};

/**
 * A native <button>: keyboard-focusable, visible focus ring, `type` defaults to "button"
 * so it never submits a form by accident. Extra classes merge via `cn`.
 */
export function Button({ variant = "primary", type = "button", className, ...props }: ButtonProps) {
  return (
    <button
      type={type}
      className={cn(BASE_CLASSES, VARIANT_CLASSES[variant], className)}
      {...props}
    />
  );
}
