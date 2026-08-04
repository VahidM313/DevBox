# Comment Banner

Turns the current line into an aligned banner comment, e.g.:

```
// ─── Generic strings ───────────────────────────────────────────────
```

## Features

- **No selection needed** — put the cursor anywhere on a line and press the
  keybinding. The line's trimmed text becomes the label; an empty line
  becomes `Section`.
- **Per-language comment styles** — `//`, `#`, `--`, `;`, `<!-- -->`, `/* */`,
  etc., picked from the file's language id. Extend/override via the
  `commentBanner.languageComments` setting.
- **Dynamic width** — instead of a hardcoded 80, it uses (in order):
  1. `commentBanner.lineLength` setting, if set (> 0)
  2. the file's first `editor.rulers` entry, if any
  3. fallback of 80
- **Idempotent** — running it again on a line that's already a banner
  re-extracts the label and rebuilds it, instead of nesting `// // ───`.
- **Multi-cursor aware.**

## Default keybinding

`Ctrl+Alt+B` (`Cmd+Alt+B` on macOS) while the editor has focus. Change it
in `package.json` → `contributes.keybindings`, or remap it in VS Code's
Keyboard Shortcuts UI (search for "Comment Banner").

## Build & run

```bash
npm install
npm run compile
```

Then press `F5` in VS Code (with this folder open) to launch an Extension
Development Host with the extension loaded — no packaging needed for local
use.

## Package as a .vsix (to install permanently)

```bash
npm install -g @vscode/vsce
vsce package
code --install-extension comment-banner-0.1.0.vsix
```

## Settings reference

| Setting                          | Default | Description                                   |
|-----------------------------------|---------|------------------------------------------------|
| `commentBanner.lineLength`        | `0`     | Fixed target width; `0` = auto (see above)     |
| `commentBanner.fillChar`          | `─`     | Fill character                                  |
| `commentBanner.padding`           | `" "`   | Spacing around the label                        |
| `commentBanner.languageComments`  | `{}`    | Per-language overrides, e.g. `{ "mylang": { "start": ";;", "end": "" } }` |
