# Nooks Demo Video Design Specification

## Overview
A studio-grade, buttery-smooth 18-second promotional demo video (1920x1080 @ 60fps) for **Nooks**, the native macOS menu bar app that brings names to Spaces, instant Dynamic Island switching, and focused window-parking workspaces.

Built using **Remotion** (React, TypeScript, CSS) to achieve frame-deterministic, native-feeling 60fps spring animations without screen capture artifacts, rendered to high-definition H.264 MP4.

---

## 1. Narrative & Storyboard (18s / 1080 Frames @ 60fps)

### Act 1: The Problem — Desktops Chaos (0s – 4.0s | Frames 0–240)
* **Scene:** A macOS desktop setup with multiple generic unnamed desktops (Desktop 1, Desktop 2, Desktop 3, Desktop 4).
* **Action:**
  * Cursor rapidly swiping/hopping back and forth between generic desktop thumbnails in Mission Control / Desktop switcher.
  * Windows are scattered across desktops with no names attached.
  * Searching motion of the cursor looking for the chat or code window.
* **On-screen Copy:** *"Which desktop was that again?"*
* **Mood:** Frustration, clutter, and wasted seconds searching.

### Act 2: Nooks Spaces & Dynamic Island Switcher (4.0s – 9.0s | Frames 240–540)
* **Scene:** The top center of the screen (the Mac display notch).
* **Action:**
  * The mouse pointer glides up to the notch hotspot.
  * **Hover Switcher / Dynamic Island** expands fluidly downward using macOS spring physics (`response: 0.28, dampingFraction: 0.82`):
    * Distinctive colored badges emerge: `1 · Code`, `2 · Chat`, `3 · Design`.
  * The cursor clicks `2 · Chat`.
  * Camera glides as the entire desktop cleanly switches over to Desktop 2.
  * The menu bar updates seamlessly with the active space name and color accent bar.
* **On-screen Copy:** *"Name your Spaces. Jump in one click."*
* **Mood:** Instant clarity, seamless elegance.

### Act 3: Workspaces & Window Parking (9.0s – 14.0s | Frames 540–840)
* **Scene:** Virtual camera punches in toward the Nooks main window (`Palette.ink` dark theme).
* **Action:**
  * Shows the "Workspaces" interface: a workspace called **Focus** with assigned apps.
  * Cursor toggles **Focus**.
  * Instantly, secondary background windows (chat, music, browser tabs) smoothly animate and park off-screen.
  * Only the primary code editor remains front and center in pristine focus.
  * Menu bar badge shows `◫ Focus`.
* **On-screen Copy:** *"One click hides the rest. Zero distractions."*
* **Mood:** Total calm and focus.

### Act 4: Outro & Call to Action (14.0s – 18.0s | Frames 840–1080)
* **Scene:** Camera pulls back smoothly to display the full desk setup in cinematic lighting.
* **Action:**
  * The official Nooks logo floats into center stage with an ambient indigo/purple glow.
  * Feature pills fade in:
    * `Native Swift`
    * `No SIP Changes`
    * `No Dependencies`
  * Title & Call-to-action:
    * **Nooks**
    * *Download for macOS 13+*
* **Mood:** Authoritative, high quality, inspiring.

---

## 2. Visual Design System & Aesthetics

### Color Palette & Tokens (Faithful to Nooks SwiftUI Source)
* **Background Ink:** `#0b0a18` (`Palette.ink` rgb 0.043, 0.039, 0.094)
* **Accent:** `#948cff` (`Palette.accent` rgb 0.58, 0.55, 1.0)
* **Surface:** `rgba(255, 255, 255, 0.055)`
* **Borders / Separators:** `rgba(255, 255, 255, 0.09)`
* **Text High / Muted:** `rgba(255, 255, 255, 0.92)` / `rgba(255, 255, 255, 0.60)`
* **Desktop Badge Tints:**
  * Space 1 (Code): `#4e82ee` (Blue)
  * Space 2 (Chat): `#8e5bf5` (Purple)
  * Space 3 (Design): `#ec5d57` (Coral/Red)
  * Space 4 (Notes): `#3fb950` (Green)

### Animation System
* Remotion `spring()` curves with macOS damping constants:
  * Island expansion: `fps: 60, config: { damping: 15, mass: 0.8, stiffness: 120 }`
  * Window parking glide: smooth horizontal/vertical slide with bezier easing off-screen.
  * Camera pan/zoom: cubic easing (`interpolate(frame, ...)` with spring dampening).

---

## 3. Component Architecture

```
video/
├── package.json
├── remotion.config.ts
├── tsconfig.json
└── src/
    ├── index.ts               # Remotion root entry
    ├── Root.tsx               # Composition registry (1920x1080 @ 60fps, 1080 frames)
    ├── NooksDemo.tsx          # Main timeline & sequence controller
    ├── components/
    │   ├── MacDesktop.tsx     # Wallpaper, shadows, desktop canvas
    │   ├── MenuBar.tsx        # Top status bar with dynamic Nooks title & color bar
    │   ├── NotchSwitcher.tsx  # Dynamic Island dropdown with space badges & names
    │   ├── MacWindow.tsx      # Window chrome, traffic lights, content mockups
    │   ├── NooksWindow.tsx    # Nooks main dark UI (Spaces and Workspaces views)
    │   ├── MouseCursor.tsx    # Smoothly animated cursor with click effects
    │   ├── Camera.tsx         # Pan and zoom stage wrapper
    │   └── KineticText.tsx    # Punchy overlay text badges
    └── assets/
        └── logo.png           # Official Nooks logo
```

---

## 4. Execution & Rendering Pipeline

* **Dependencies:** `remotion`, `@remotion/cli`, `react`, `react-dom`, `@types/react`.
* **Render Command:**
  ```bash
  npx remotion render src/index.ts NooksDemo out/nooks-demo.mp4 --concurrency=4
  ```
* **Output Artifacts:**
  * `video/out/nooks-demo.mp4` (1080p, 60fps H.264)
  * `video/out/nooks-demo-poster.png` (Keyframe preview)
* **Agent Harness Rule:** If spawning any external workers through `cntctr`, use only other `agy` agents (`harness: "agy"`).

---

## 5. Verification & Acceptance Criteria

1. **Resolution & Framerate:** Exactly 1920x1080, 60fps, 18.0 seconds (1080 frames).
2. **Visual Fluidity:** Zero stutter, smooth spring physics on the notch expansion and window parking.
3. **Accuracy to Nooks:** Exact matching of Nooks' colors, menu bar representation, notch island, and workspaces logic.
4. **Deliverable Validated:** Video renders successfully to disk and passes `ffprobe` inspection.
