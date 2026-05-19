---
name: computer-use-for-windows
description: Use local Windows desktop automation tools for screenshots, mouse movement, clicks, typing, shortcut keys, cursor position, and clipboard operations.
---

# computer_use_for_windows

Use this skill when the user asks Codex to inspect or operate local Windows GUI applications.

## Backend

The plugin backend lives at `scripts/windows-computer-use.ps1` inside the plugin root.

Call actions with `-Action <tool_name>` and UTF-16LE Base64 JSON in `-ArgsBase64` when arguments are needed. Use `npm run cleanup` in the plugin root to clear scratch files and old screenshots.

## Workflow

1. Start with `screenshot` before any action that depends on the current screen.
2. Use `doctor` first when screenshot or input tools fail; it reports whether the current process can access the interactive desktop and whether cleanup is recommended.
3. Use `list_windows` or `get_active_window` when the action depends on a specific app window.
4. Use `focus_window` before keyboard input when the intended app is known.
5. Use `open_url` for browser navigation when a URL is known.
6. Use the smallest possible action: one click, one scroll, one drag, one key chord, or one text insertion.
7. Verify state with another `screenshot` after any write action.
8. Avoid interacting with password fields, payment flows, destructive dialogs, or private content unless the user explicitly asks and confirms the exact action.
9. Prefer clipboard paste for longer text, and direct key chords for navigation shortcuts.

## Coordinate Guidance

Coordinates are absolute screen pixels on the primary monitor. Before clicking, inspect the latest screenshot dimensions and use visible target centers rather than edges.

For multi-monitor setups, call `screenshot` with `allScreens: true` and use the returned virtual desktop origin. Coordinates can be negative when a monitor is positioned left or above the primary display.

## Safety Defaults

If `WINDOWS_COMPUTER_USE_CONFIRM_INPUT=true`, input tools require `confirm: true`. Even when that environment flag is off, ask the user before actions that could submit forms, send messages, delete data, purchase items, change security settings, or expose secrets.

## Tool Names

Available backend actions include:

- `screenshot`
- `doctor`
- `list_screens`
- `list_windows`
- `get_active_window`
- `focus_window`
- `open_url`
- `get_cursor`
- `mouse_move`
- `mouse_click`
- `mouse_drag`
- `mouse_scroll`
- `type_text`
- `key_press`
- `clipboard_set`
- `clipboard_clear`
- `clipboard_get`
