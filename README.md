<p align="center">
  <img src="logo.png" alt="Nooks" width="128">
</p>

<h1 align="center">Nooks</h1>

<p align="center">Name your macOS desktops, jump between them, and group windows into workspaces.<br>A small menu bar app. No dependencies, no SIP changes.</p>

<p align="center">
  <a href="https://github.com/Chieler/Nooks/releases/latest"><b>Download for macOS</b></a>
</p>

## Features

- **Name your Spaces.** Give each desktop a name. Names follow the desktop when you reorder them.
- **Switch from the menu bar.** Numbered, color-coded desktops in one click.
- **Hover switcher.** Move the pointer to the top center of the screen for a quick desktop strip.
- **Workspaces.** Group windows, then show one group and hide the rest, without opening new desktops.

## Install

1. Download `Nooks.dmg` from the [latest release](https://github.com/Chieler/Nooks/releases/latest).
2. Open it and drag **Nooks** to **Applications**.
3. Launch Nooks. It lives in the menu bar.

Requires macOS 13 or later. Universal binary for Apple silicon and Intel. Signed and notarized.

## First launch: allow Accessibility

Nooks needs Accessibility access to read window titles and switch desktops. macOS only lets you grant this yourself.

1. Click **Open Accessibility Settings** in the Nooks window.
2. Switch on **Nooks** in the list.
3. Come back. The window updates by itself.

If Nooks is listed but still asks, select it, click **−**, then add it again.

## How to use

### Spaces

Open Nooks from the menu bar and pick **Spaces**.

- Type in a card to name a desktop. The name shows up in the menu bar menu.
- Click **Switch** on a card, or choose a desktop from the menu bar.
- Create more desktops in Mission Control with the **+** button.

### Workspaces

Pick **Workspaces**.

1. Type a name under **New workspace** and press Return.
2. In the window list, choose a workspace for each window.
3. Click a workspace to show it. Windows that are not in it are hidden.
4. Click it again, or use the menu bar, to bring everything back.

Hover a workspace and click **✕**, or right-click it, to delete it. Deleting restores any hidden windows first.

Hidden windows are parked just off screen, not closed or minimized. Nooks saves their original positions before moving them, and restores them when you quit, change desktops, or change displays. If Nooks ever crashes, reopen it and your windows come back.

## Good to know

- Workspace names are saved. Window assignments last until you quit.
- Windows on other desktops and fullscreen windows are left alone.
- A thin sliver of a hidden window can stay visible at the screen corner.
- Nooks uses undocumented macOS APIs, so it is not on the Mac App Store and a macOS update can break parts of it. Please open an issue if it does.

## Build from source

Requires Xcode or the Swift command-line tools.

```sh
bash scripts/build.sh      # debug build to dist/Nooks.app
bash scripts/release.sh    # signed, notarized dmg (needs your own Developer ID)
swift test
```

`release.sh` expects a Developer ID identity and a `notarytool` keychain profile. Override them with `SIGN_IDENTITY` and `NOTARY_PROFILE`.

Diagnostics that do not move any windows:

```sh
.build/debug/Nooks --diagnose
.build/debug/Nooks --self-check
```

## Credits

Ideas from [SpaceNamer](https://github.com/brandaorafael/SpaceNamer), [Hammerspoon hs.spaces](https://www.hammerspoon.org/docs/hs.spaces.html), [Rename Spaces](https://github.com/egwoo/rename-spaces), and [AeroSpace](https://nikitabobko.github.io/AeroSpace/guide#emulation-of-virtual-workspaces). Nooks is a new implementation and does not include code from those projects.
