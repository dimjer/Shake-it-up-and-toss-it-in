# Toss — Project Handoff

**One line:** a tiny native macOS menu-bar app. Shake the mouse and a sci-fi "black hole" opens; toss files or screenshots into it, then drag them from the hole into the Claude Code terminal. The app copies every dropped file, so screenshots no longer vanish when macOS deletes its temporary copy.

**Status:** working, in daily use. Verified end-to-end on 23 October 2026: screenshot → shake → drop into hole → drag into terminal → Claude reads the file.
**Version / date:** 1.0 · handoff written 23 October 2026, updated 24 October 2026.
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
| `Sources/Core.swift` | Shared: `Settings`, `ShelfStyle`, `Store` (stash), `ShakeDetector`, `FileDragSource`, `DropView`, and `ShelfPanel` — the base window with the 4-button bar (copy paths · clear · style · close) and open/close. |
| `Sources/HoleStyle.swift` | Style "Black Hole": `OrbitTile`, `HoleCore`, `BlackHoleFX`, `HolePanel`. |
| `Sources/KittenStyle.swift` | Style "Kittens": pixel `Kitten`s (coat = file type) and a small wicker `Basket`; up to 4 kittens sit in it, the rest around it. |
| `Sources/ClassicStyle.swift` | Style "Classic": frosted macOS panel with an icon grid and a drag-all handle. |
| `Tools/make_icon.swift` | Renders the app icon (black hole: dark starry squircle, glowing orange halo + tilted accretion disk, amber down arrow inside) into an `.iconset`. |
| `build.sh` | Compiles, generates the icon, ad-hoc signs, installs to `~/Applications/Toss.app`, relaunches. **Run after every change.** |
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
- **Another Mac:** it has no signing key, so its commits would be rejected by `safe-pull.sh`. Either copy the key, or create a new one there and add its public key to `allowed_signers` on both Macs.
- **To do:** make sure 2FA is on for the GitHub account.

## 6. Tuning knobs

- Shake sensitivity: `ShakeDetector.tick()`, where `threshold` (px per swing: 30 when dragging, 35 otherwise), `needed` (3 reversals) and the 0.7 s window are set.
- Hole look: `BlackHoleFX`, which holds the colours (`hot`), disk tilt (`1.27` rad), spin speeds and particle emitter.
- Orbit: `HolePanel`, which sets `orbitR` (150), the speeds in `tickOrbit()` (0.3 normal, 0.08 near cursor), tile size (44 / 34 when more than 12 files) and label width (92).

---

## 7. Known limitations / ideas for next time

- With 10 or more files, long names on the orbit can slightly overlap. Options: shorter labels, a wider orbit, or a second ring.
- No global hotkey yet. It would be easy to add with Carbon `RegisterEventHotKey`, also with no permissions.
- Ad-hoc signed and arm64 only. To run on another Mac, rebuild there with `./build.sh`.
- The visuals were tuned from a single screenshot on a light wallpaper. File names now sit on dark pills, but this hasn't been re-checked visually since that change.
