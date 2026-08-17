/**
 * Resizable panel group. PORTED FROM HypeTerminal, not reimplemented.
 *
 * Source: `apps/terminal/src/components/ui/resizable.tsx` in the HypeTerminal repo, a 41-line thin
 * wrapper over `react-resizable-panels` (they pin 4.6.0; this project pins the same version rather
 * than the 4.12.2 latest, so the behaviour matches the product being copied).
 *
 * WHY THIS REPLACES WHAT WAS HERE: the previous layout used `flex-wrap` on the workspace so a sidebar
 * could drop below the main column at narrow widths. That is not their pattern, and it produced real
 * clipping: measured at a 632px viewport, `main` had clientHeight 466 against scrollHeight 6945, with
 * 683 elements extending past the viewport and no scroll region to reach them. Content was simply
 * unreachable.
 *
 * Their answer to "not enough width" is not wrapping. It is:
 *   - resizable panels side by side, each `h-full flex flex-col`, so the operator sets the split;
 *   - a body height of `max(calc(100dvh - chrome), minHeightPx)` (`main-workspace.tsx:28-30`), so a
 *     small viewport makes the body TALLER than the screen and the page scrolls rather than clipping;
 *   - `overflow-x-auto scrollbar-none` on strips that cannot shrink (`main-workspace.tsx:41`).
 *
 * Adaptations, all mechanical: their `bg-stroke-weak` and `bg-brand/30` Tailwind colour utilities are
 * written here against this project's CSS variables, because this project wires tokens as variables
 * rather than through their layer-3 `@theme` colour mapping. The structure, data-slots, aria handling
 * and the `withHandle` grip are theirs unchanged.
 */

import * as ResizablePrimitive from "react-resizable-panels";
import { cn } from "./primitives";

export function ResizablePanelGroup({ className, ...props }: ResizablePrimitive.GroupProps) {
  return (
    <ResizablePrimitive.Group
      data-slot="resizable-panel-group"
      className={cn("flex h-full w-full aria-[orientation=vertical]:flex-col", className)}
      {...props}
    />
  );
}

export function ResizablePanel({ ...props }: ResizablePrimitive.PanelProps) {
  return <ResizablePrimitive.Panel data-slot="resizable-panel" {...props} />;
}

export function ResizableHandle({
  withHandle,
  className,
  ...props
}: ResizablePrimitive.SeparatorProps & { withHandle?: boolean }) {
  return (
    <ResizablePrimitive.Separator
      data-slot="resizable-handle"
      className={cn(
        "group relative flex w-px items-center justify-center",
        "after:absolute after:inset-y-0 after:left-1/2 after:w-1 after:-translate-x-1/2",
        "focus-visible:outline-hidden",
        "aria-[orientation=horizontal]:h-px aria-[orientation=horizontal]:w-full",
        "aria-[orientation=horizontal]:after:left-0 aria-[orientation=horizontal]:after:h-1",
        "aria-[orientation=horizontal]:after:w-full aria-[orientation=horizontal]:after:translate-x-0",
        "aria-[orientation=horizontal]:after:-translate-y-1/2",
        "[&[aria-orientation=horizontal]>div]:rotate-90",
        "bg-[var(--stroke-weak)]",
        "data-[resize-handle-state=hover]:bg-[var(--stroke-focus)]",
        "data-[resize-handle-state=drag]:bg-[var(--stroke-focus)]",
        className,
      )}
      {...props}
    >
      {withHandle && (
        <div
          className={cn(
            "z-10 flex h-6 w-1 shrink-0 bg-[var(--stroke-strong)]",
            "group-data-[resize-handle-state=hover]:bg-[var(--stroke-focus)]",
            "group-data-[resize-handle-state=drag]:bg-[var(--stroke-focus)]",
          )}
        />
      )}
    </ResizablePrimitive.Separator>
  );
}
