# Toss — Project Handoff

**One line:** a tiny native macOS menu-bar app. Shake the mouse and a shelf pops up (a sci-fi black hole, a basket of pixel kittens, or a plain macOS panel); toss files or screenshots onto it, then drag them into the Claude Code terminal or any other app. The app copies every dropped file, so screenshots no longer vanish when macOS deletes its temporary copy.

**Status:** working, in daily use. Verified end-to-end on 23 October 2026 (black hole): screenshot → shake → drop into hole → drag into terminal → Claude reads the file. The three-style version (25 October 2026) builds, launches and renders correctly; the live drag/settings flow is still to be confirmed by hand (see §7).
**Version / date:** 1.1 · handoff written 23 October 2026, updated 25 October 2026.
**Repo:** https://github.com/dimjer/Toss (public, `main`; formerly `Shake-it-up-and-toss-it-in`, GitHub redirects the old URL)
**Owner:** Dima · built with Claude Code.

---

## 1. The problem it solves

Dragging the macOS screenshot thumbnail straight into the terminal pastes a path under `/var/folders/.../NSIRD_screencaptureui_*`. macOS deletes that temp file right away (and Claude Code can't read there anyway), so Claude gets a dead link. Toss sits in between: it takes the drop, copies the file to `~/.toss`, and hands out a stable path.

---

## 2. How it works (current behaviour)

- **Summon:** shake the mouse left-right, with or without dragging. Detection polls the cursor (60 Hz while it moves, 10 Hz once it rests) and needs **no macOS permissions**. You can also use the menu-bar icon → *Show Shelf*.
- **Styles:** *Black Hole* (files spiral in and orbit), *Kittens* (a pixel kitten per file, coat = file type; up to 4 sit in a small basket, the rest around it) and *Classic* (frosted macOS panel with an icon grid). Picked from the gear button or the menu bar; switching keeps the files and the window position.
- **Drop:** anything dropped is copied into `~/.toss`: files, folders, file promises (Photos, browsers), raw image data saved as PNG, and text saved as TXT.
- **Take one:** drag a single file (thumbnail / kitten / icon) out. Dragging **copies**: the file stays on the shelf, so it can go into several windows.
- **Take all:** drag the stack-with-count button at the left of the button bar (works in every style). Also: the hole's black centre, or the kitten basket itself.
- **Buttons:** take all · *copy paths* (shell-escaped, ready to paste) · *clear files* (window stays open) · *style & settings* · *close* (also Esc). Right-clicking a file gives *copy path* / *copy as image* / *show in Finder* / *remove*.
- **Closing (setting):** after 3 / 10 (default) / 30 s idle, or *only with ×*. Idle = cursor away from the shelf and no mouse button held, so a drag into another app never gets cut off. An empty shelf from a stray shake closes after 2 s (unless *only with ×*).
- **Clearing (setting):** *only with the trash button* (default) or *when the shelf closes*. Either way `~/.toss` is wiped on every app launch, so nothing survives a restart or reboot.
- **Menu-bar icon:** follows the style: a hand-drawn black hole (template image in `ShelfStyle.holeIcon`), `cat.fill`, `tray.full.fill`.
- **Menu-bar options:** *Show Shelf*, *Copy Paths*, *Clear Shelf*, *Shelf Settings* (style, closing, clearing), *Shake Without Dragging Too* (on by default), *Launch at Login*, *Open Stash Folder*, *Quit*.

---

## 3. Files

| Path | What |
|---|---|
| `Sources/main.swift` | App entry: `AppDelegate` (menu bar, shake → show, style switching). |
| `Sources/Core.swift` | Shared: `Settings`, `ShelfStyle`, `Store` (stash), `ShakeDetector`, `FileDragSource`, `DropView`, and `ShelfMenu` (style / closing / clearing menu), `GrabAllHandle`, and `ShelfPanel` — the base window with the button bar (take all · copy paths · clear · settings · close), open/close and clear-on-close. Each style subclasses `ShelfPanel` and overrides its hooks (`reload`, `didDrop`, `setHungry`, …). |
| `Sources/HoleStyle.swift` | Style "Black Hole": `OrbitTile`, `HoleCore`, `BlackHoleFX`, `HolePanel`. |
| `Sources/KittenStyle.swift` | Style "Kittens": pixel `Kitten`s (coat = file type) and a small wicker `Basket`; up to 4 kittens sit in it, the rest around it. |
| `Sources/ClassicStyle.swift` | Style "Classic": frosted macOS panel (`NSVisualEffectView`) with an icon grid and a dashed drop zone. |
| `Tools/make_icon.swift` | Renders the app icon (three pixel kittens in a wicker basket on a pink squircle) into an `.iconset`. |
| `build.sh` | Compiles `Sources/*.swift`, generates the icon, ad-hoc signs, installs to `~/Applications/Toss.app`, waits for the old copy to quit, relaunches. **Run after every change.** |
| `safe-pull.sh` | The only way to update from GitHub (see §5). |
| `build/` | Build output (disposable, git-ignored). |

---

## 4. Environment setup (already done on this Mac)

- `~/.claude/settings.json` → `permissions.additionalDirectories: ["~/.toss"]`, so Claude Code can read dropped files in **any** project without a prompt.
- Recommended: turn off macOS *System Settings → Accessibility → Display → Pointer → "Shake mouse pointer to locate"*, because it fires on the same gesture and enlarges the cursor.

---

## 5. Git & security

- **Signed commits:** the repo is configured locally (`git config`, not global) to sign every commit with the SSH key `~/.ssh/id_ed25519_signing`. That key exists only on this Mac and is NOT uploaded to GitHub.
- **Trusted keys:** `~/.config/git/allowed_signers`, kept outside the repo so a compromised GitHub can't change it.
- **Updating:** never `git pull`. Run `./safe-pull.sh`. It fetches, refuses if any new commit isn't signed by a trusted key or history was rewritten, flags suspicious lines (curl, base64, eval, osascript, LaunchAgents, Keychain…) and binary files, then fast-forwards only after a "y". Then run `./build.sh`.
- **GitHub side:** only `dimjer` has write access (no collaborators, no deploy keys). Ruleset `protect-main` blocks force-push and deleting `main`. `gh` CLI is installed and logged in as `dimjer`.
- **Unsigned commit in history:** `808a55d` (kitten basket, pushed from elsewhere) is not signed. It is already in `main` here; on another Mac `safe-pull.sh` will refuse it, so pull that one update by hand after reviewing it.
- **Another Mac:** it has no signing key, so its commits would be rejected by `safe-pull.sh`. Either copy the key, or create a new one there and add its public key to `allowed_signers` on both Macs. An existing clone there should also run `git remote set-url origin https://github.com/dimjer/Toss.git`.
- **To do:** make sure 2FA is on for the GitHub account.

## 6. Tuning knobs

- Shake sensitivity: `ShakeDetector.tick()`, where `threshold` (px per swing: 30 when dragging, 35 otherwise), `needed` (3 reversals) and the 0.7 s window are set. Polling rates: `ShakeDetector.fast` / `slow`.
- Auto-close: `AppDelegate.watchIdle()` (the 2 s rule for an empty shelf, the 0.25 s check). Choices offered: `ShelfMenu.fill()`. Defaults: `Settings.d` (`autoClose` 10, `clearOnClose` off, style `kittens`).
- Hole look: `BlackHoleFX`, which holds the colours (`hot`), disk tilt (`1.27` rad), spin speeds and particle emitter.
- Orbit: `HolePanel`, which sets `orbitR` (150), the speeds in `tickOrbit()` (0.3 normal, 0.08 near cursor), tile size (44 / 34 when more than 12 files) and label width (92).
- Kittens: `BasketPanel` — `insideMax` (4 in the basket), kitten size `px` (3) and `tileW` (60), the in-basket offsets in `seat(of:count:)`, and the ring around the basket (`ring` radii 205×172, 20° steps, 13 seats before kittens pile up). Basket scale: `BasketCore.px` (4). Coats per file type: `Coat.forFile`.
- Classic: `ClassicPanel.size` (344×360, three rows visible), `cols` (4), tile size `ClassicTile.size`.
- Menu-bar black hole icon: `ShelfStyle.holeIcon` (drawn in code, template image).

---

## 7. Known limitations / ideas for next time

- **To confirm by hand** (only the static rendering was checked): style switching from the gear menu, dragging a single kitten / the stack button into another app, the idle timer with each setting, Classic in light and dark mode, and the new menu-bar black hole icon at real size.
- Dragging out no longer removes files; to drop one file from the shelf use right-click → *Remove*.
- With 10 or more files, long names on the orbit can slightly overlap. Options: shorter labels, a wider orbit, or a second ring.
- Kittens: past 17 files (4 in the basket + 13 around it) kittens pile on top of each other.
- The black hole still runs its orbit timer at 60 Hz while open (stops when closed); kittens and Classic have no timers.
- No global hotkey yet. It would be easy to add with Carbon `RegisterEventHotKey`, also with no permissions.
- Ad-hoc signed and arm64 only. To run on another Mac, rebuild there with `./build.sh`.
- The visuals were tuned from a single screenshot on a light wallpaper. File names now sit on dark pills, but this hasn't been re-checked visually since that change.
