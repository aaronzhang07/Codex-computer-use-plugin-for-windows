# computer_use_for_windows

`computer_use_for_windows` is a Windows-first Codex plugin that exposes local desktop automation tools over MCP. It can inspect the desktop through screenshots and window metadata, then act through mouse, keyboard, clipboard, scrolling, dragging, URL opening, and focused-window helpers.

The plugin is intentionally local-only. It uses Node.js for the MCP stdio server and PowerShell/.NET/Win32 APIs for the Windows backend. It has no third-party runtime dependencies.

## Install

From this repository:

```powershell
npm run check
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-codex.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-codex-cache.ps1
```

Restart Codex if the plugin picker does not refresh immediately, then type `@computer_use_for_windows`.

## Design Flow

1. **Observe**
   - Capture the active desktop as a PNG.
   - Return the image path, screen bounds, and cursor position.
   - Let Codex reason from pixels before taking an action.

2. **Decide**
   - The model chooses a small, explicit action: move, click, type, key chord, or clipboard change.
   - Tool schemas keep every operation narrow and auditable.

3. **Act**
   - The MCP server invokes `scripts/windows-computer-use.ps1`.
   - The PowerShell layer uses built-in .NET and Win32 APIs, so the first version has no package install step.

4. **Verify**
   - After a write action, call `screenshot` again.
   - Compare the resulting state with the intended state before continuing.

5. **Guard**
   - Input actions are disabled by policy if `WINDOWS_COMPUTER_USE_CONFIRM_INPUT=true` and the caller has not passed `confirm: true`.
   - Future versions should add app allowlists, typed-text redaction, and per-action confirmation prompts for risky UI contexts.

## Current Tools

- `screenshot`: save a PNG of the primary screen or full virtual desktop and return metadata; optionally return MCP image content.
- `doctor`: run a no-side-effect environment self-check for screen/window metadata, cursor read access, screenshot capture, and runtime file usage.
- `list_screens`: list attached displays and virtual desktop bounds.
- `list_windows`: list visible top-level windows with titles, handles, process ids, and rectangles.
- `get_active_window`: return the current foreground window metadata.
- `focus_window`: bring a visible window to foreground by handle, process id, or title substring.
- `open_url`: open a URL in the Windows default browser.
- `get_cursor`: return the current cursor coordinates.
- `mouse_move`: move the cursor to an absolute coordinate.
- `mouse_click`: click an absolute coordinate or the current cursor position.
- `mouse_drag`: drag between two absolute coordinates.
- `mouse_scroll`: scroll the mouse wheel at the current or specified coordinate.
- `type_text`: type text into the focused application; optionally bind the write to a known `targetWindowHandle`.
- `key_press`: send a key or key chord such as `Ctrl+L`; optionally guard the target window before sending.
- `clipboard_set`: set Unicode text on the Windows clipboard.
- `clipboard_clear`: clear the Windows clipboard.
- `clipboard_get`: read Unicode text from the Windows clipboard.

## Local Check

```powershell
npm run check
npm run smoke:doctor
```

For a full controlled GUI test suite:

```powershell
npm test
```

The full suite opens temporary Notepad windows and exercises screenshot, clipboard, mouse, keyboard, and text-writing paths. Do not run it while typing into another sensitive application.

The MCP server intentionally avoids third-party Node dependencies in this first version. It implements the small subset of JSON-RPC messages needed by Codex MCP clients directly over stdio.

## Safety Environment Variables

- `WINDOWS_COMPUTER_USE_CONFIRM_INPUT=true`: input tools require `confirm: true`.
- `WINDOWS_COMPUTER_USE_ALLOW_WINDOW=<regex>`: mouse/keyboard tools only run when the active window title or process name matches.
- `WINDOWS_COMPUTER_USE_BLOCK_WINDOW=<regex>`: mouse/keyboard tools are blocked when the active window title or process name matches.
- `expectedWindowTitle`: per-call guard for mouse, keyboard, and text tools.
- `targetWindowHandle`: per-call handle that lets guarded input tools refocus and verify a known target window before acting.

## Temporary Files and Cleanup

Screenshots are stored under `.screenshots/` and smoke-test scratch files are stored under `.scratch/`. Both paths are ignored by Git.

```powershell
npm run cleanup:dry
npm run cleanup
```

Default cleanup behavior:

- Remove screenshots older than 24 hours.
- Keep at least the latest 50 screenshots.
- Remove scratch files.
- Refuse to delete anything outside the plugin's `.screenshots/` and `.scratch/` directories.
- Report scanned, kept, and removed file counts plus byte totals.

## Privacy

Runtime screenshots and scratch files are stored locally under `.screenshots/` and `.scratch/`. These directories are ignored by Git and can be removed with `npm run cleanup`.
