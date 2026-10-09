import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

/**
 * Joins class names (clsx: strings, arrays, `{ class: condition }`) and resolves
 * conflicting Tailwind utilities so the last one wins (`cn("px-4", "px-8")` → `"px-8"`).
 */
export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}
