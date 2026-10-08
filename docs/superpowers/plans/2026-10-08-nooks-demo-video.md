# Nooks Demo Video Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Remotion video project and render a buttery-smooth 18-second (1080 frames @ 60fps) 1080p promotional video showcasing Nooks' macOS Spaces naming, Dynamic Island hover switcher, and workspace window parking.

**Architecture:** A standalone React/TypeScript Remotion project under `video/` with modular macOS desktop UI components, SwiftUI-accurate spring animations (`spring()`, `interpolate()`), a virtual camera rig, simulated mouse physics, and automated MP4 rendering via `@remotion/cli` and `ffmpeg`.

**Tech Stack:** React 19, TypeScript, Remotion 4.x, Remotion CLI, Chromium headless, FFmpeg.

**Spec:** [docs/superpowers/specs/2026-10-08-nooks-demo-video-design.md](file:///Users/chielerli/programming/spacesort/docs/superpowers/specs/2026-10-08-nooks-demo-video-design.md)

## Global Constraints

- Output video must be exactly 1920x1080 resolution, 60fps, 1080 frames (18.0s).
- Colors and typography must faithfully match Nooks' SwiftUI code (`#0b0a18` ink background, `#948cff` accent, exact `SpaceTint` badge colors).
- Any subagent/worker orchestration via `cntctr` must strictly use only `agy` harness (`harness: "agy"`).
- All video source code lives inside `video/` to keep the root Swift repository clean.

## Review Focus

- Spring physics damping matches native macOS feel without abrupt snaps or jitter.
- The Dynamic Island notch expansion correctly anchors to the top center and expands smoothly.
- Window parking in Act 3 glides windows off-screen smoothly while keeping the active window untouched.
- Rendered MP4 is compatible with standard web players (H.264 / AAC, yuv420p pixel format).
- Outro clearly displays the official logo and core value propositions.

---

### Task 1: Project Scaffolding & Asset Setup

**Files:**
- Create: `video/package.json`
- Create: `video/tsconfig.json`
- Create: `video/remotion.config.ts`
- Create: `video/public/logo.png`
- Create: `video/src/index.ts`
- Create: `video/src/Root.tsx`

**Interfaces:**
- Produces: Remotion root composition `NooksDemo` configured at 1920x1080, 60fps, 1080 durationInFrames.

- [ ] **Step 1: Create package.json and tsconfig.json in `video/`**
- [ ] **Step 2: Copy `logo.png` into `video/public/logo.png`**
- [ ] **Step 3: Install Remotion, React, and TypeScript dependencies**
  Run: `cd video && npm install`
- [ ] **Step 4: Create `remotion.config.ts`, `src/index.ts`, and `src/Root.tsx` with stub composition**
- [ ] **Step 5: Verify Remotion bundler builds without errors**
  Run: `npx remotion compositions` in `video/`
  Expected: `NooksDemo (1920x1080, 60fps, 1080 frames)`
- [ ] **Step 6: Commit**
  ```bash
  git add video/
  git commit -m "feat(video): initialize remotion project scaffolding"
  ```

---

### Task 2: macOS Desktop Environment & Chrome Components

**Files:**
- Create: `video/src/theme.ts`
- Create: `video/src/components/MacDesktop.tsx`
- Create: `video/src/components/MenuBar.tsx`
- Create: `video/src/components/MouseCursor.tsx`
- Create: `video/src/components/CinematicCamera.tsx`

**Interfaces:**
- Consumes: `theme.ts` (colors, typography tokens from Nooks SwiftUI source).
- Produces:
  - `<MacDesktop />`: dark ambient wallpaper background, dock or desktop container.
  - `<MenuBar currentSpaceTitle={string} activeWorkspace={string | null} spaceNumber={number} />`: macOS top bar with clock, Apple logo, system tray, and dynamic Nooks item.
  - `<MouseCursor position={{ x: number, y: number }} clicking={boolean} />`: SVG macOS arrow cursor with click scale down and ripple.
  - `<CinematicCamera scale={number} x={number} y={number} />`: smooth viewport transform wrapper.

- [ ] **Step 1: Define design tokens in `video/src/theme.ts`**
- [ ] **Step 2: Implement `<MacDesktop />` with dark macOS gradient wallpaper**
- [ ] **Step 3: Implement `<MenuBar />` with dynamic Nooks title and color bar indicator**
- [ ] **Step 4: Implement `<MouseCursor />` with smooth positioning and click pulse**
- [ ] **Step 5: Implement `<CinematicCamera />` stage wrapper**
- [ ] **Step 6: Render a single preview frame (frame 0) to verify visual fidelity**
  Run: `cd video && npx remotion still NooksDemo out/frame-0.png --frame=0`
  Expected: `out/frame-0.png` successfully created with desktop and menu bar visible.
- [ ] **Step 7: Commit**
  ```bash
  git add video/src/theme.ts video/src/components/
  git commit -m "feat(video): add macos desktop, menubar, cursor, and camera components"
  ```

---

### Task 3: Nooks UI & Interaction Components

**Files:**
- Create: `video/src/components/SpaceBadge.tsx`
- Create: `video/src/components/NotchSwitcher.tsx`
- Create: `video/src/components/MacWindow.tsx`
- Create: `video/src/components/NooksWindow.tsx`

**Interfaces:**
- Consumes: `theme.ts`, `SpaceBadge.tsx`.
- Produces:
  - `<NotchSwitcher isExpanded={boolean} activeSpaceId={number} onHoverItem={number | null} />`: Dynamic island expanding pill matching `IslandCardShape`, containing colored desktop badges `1 · Code`, `2 · Chat`, `3 · Design`.
  - `<MacWindow id={string} title={string} appName={string} x={number} y={number} width={number} height={number} parked={boolean} parkDirection={"left" | "right" | "bottom"} />`: macOS window chrome with traffic light buttons and dark window contents.
  - `<NooksWindow tab={"spaces" | "workspaces"} activeWorkspace={string | null} />`: Nooks main app window matching `Palette.ink` (#0b0a18), sidebar navigation, Spaces rename cards, and Workspaces list.

- [ ] **Step 1: Implement `<SpaceBadge />` with Nooks desktop color tinting**
- [ ] **Step 2: Implement `<NotchSwitcher />` with spring-driven dynamic island expansion**
- [ ] **Step 3: Implement `<MacWindow />` with smooth parking animation when `parked=true`**
- [ ] **Step 4: Implement `<NooksWindow />` matching Nooks' SwiftUI layout**
- [ ] **Step 5: Render still frames testing NotchSwitcher expanded and NooksWindow open**
  Run: `cd video && npx remotion still NooksDemo out/test-ui.png --frame=300`
  Expected: Still frame renders showing crisp island switcher and windows.
- [ ] **Step 6: Commit**
  ```bash
  git add video/src/components/
  git commit -m "feat(video): add notch switcher, mac window, and nooks ui components"
  ```

---

### Task 4: Scene Choreography & Kinetic Overlays

**Files:**
- Create: `video/src/components/KineticBadge.tsx`
- Create: `video/src/scenes/Act1Chaos.tsx`
- Create: `video/src/scenes/Act2NotchSwitcher.tsx`
- Create: `video/src/scenes/Act3Workspaces.tsx`
- Create: `video/src/scenes/Act4Outro.tsx`
- Modify: `video/src/NooksDemo.tsx`

**Interfaces:**
- Consumes: Components from Tasks 2 & 3.
- Produces: Complete 18-second choreographed sequence orchestrated in `<NooksDemo />` via `<Sequence />`.

- [ ] **Step 1: Implement `<KineticBadge />` for punchy animated text overlays**
- [ ] **Step 2: Implement `Act1Chaos` (0s–4s, frames 0–240): Unnamed generic desktops (Desktop 1, 2, 3), frantic swiping, "Which desktop was that again?"**
- [ ] **Step 3: Implement `Act2NotchSwitcher` (4s–9s, frames 240–540): Cursor glides to notch, Dynamic Island drops down, click `2 · Chat`, smooth space transition**
- [ ] **Step 4: Implement `Act3Workspaces` (9s–14s, frames 540–840): Nooks window opens, Workspaces tab, toggle "Focus", secondary windows glide off-screen**
- [ ] **Step 5: Implement `Act4Outro` (14s–18s, frames 840–1080): Full desktop pull-back, glowing Nooks logo, value badges, "Download for macOS 13+"**
- [ ] **Step 6: Connect all acts in `NooksDemo.tsx` with smooth transitions**
- [ ] **Step 7: Commit**
  ```bash
  git add video/src/scenes/ video/src/components/KineticBadge.tsx video/src/NooksDemo.tsx
  git commit -m "feat(video): choreograph acts 1-4 with kinetic overlays"
  ```

---

### Task 5: Video Rendering & Quality Verification

**Files:**
- Create: `video/out/nooks-demo.mp4`
- Create: `video/out/nooks-demo-poster.png`

**Interfaces:**
- Produces: High-definition 1080p 60fps MP4 file ready for production.

- [ ] **Step 1: Execute Remotion render pipeline**
  Run: `cd video && npx remotion render src/index.ts NooksDemo out/nooks-demo.mp4 --concurrency=4`
  Expected: Render completes with 1080 frames rendered into `video/out/nooks-demo.mp4`.
- [ ] **Step 2: Generate poster preview image**
  Run: `cd video && npx remotion still src/index.ts NooksDemo out/nooks-demo-poster.png --frame=960`
  Expected: `video/out/nooks-demo-poster.png` created.
- [ ] **Step 3: Verify video properties with `ffprobe`**
  Run: `ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate,duration -of json video/out/nooks-demo.mp4`
  Expected: width=1920, height=1080, r_frame_rate=60/1, duration=18.0.
- [ ] **Step 4: Inspect key frames across acts (Act 1, Act 2, Act 3, Act 4) for visual perfection**
  Run: `ffmpeg -ss 2 -i video/out/nooks-demo.mp4 -vframes 1 -q:v 2 video/out/frame-act1.png -y`
  Run: `ffmpeg -ss 6.5 -i video/out/nooks-demo.mp4 -vframes 1 -q:v 2 video/out/frame-act2.png -y`
  Run: `ffmpeg -ss 11.5 -i video/out/nooks-demo.mp4 -vframes 1 -q:v 2 video/out/frame-act3.png -y`
  Run: `ffmpeg -ss 16 -i video/out/nooks-demo.mp4 -vframes 1 -q:v 2 video/out/frame-act4.png -y`
- [ ] **Step 5: Commit video artifacts or production scripts**
  ```bash
  git add docs/superpowers/plans/2026-10-08-nooks-demo-video.md
  git commit -m "docs: finalize nooks demo video plan"
  ```
