"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.activate = activate;
exports.deactivate = deactivate;
const vscode = require("vscode");
// Built-in defaults, keyed by VS Code languageId.
// Anything not listed falls back to "//".
const DEFAULT_STYLES = {
    python: { start: '#', end: '' },
    shellscript: { start: '#', end: '' },
    yaml: { start: '#', end: '' },
    toml: { start: '#', end: '' },
    dockerfile: { start: '#', end: '' },
    makefile: { start: '#', end: '' },
    ruby: { start: '#', end: '' },
    r: { start: '#', end: '' },
    perl: { start: '#', end: '' },
    powershell: { start: '#', end: '' },
    ini: { start: ';', end: '' },
    properties: { start: '#', end: '' },
    sql: { start: '--', end: '' },
    lua: { start: '--', end: '' },
    haskell: { start: '--', end: '' },
    elm: { start: '--', end: '' },
    css: { start: '/*', end: ' */' },
    scss: { start: '//', end: '' }, // SCSS supports //, keep it simple
    less: { start: '//', end: '' },
    html: { start: '<!--', end: ' -->' },
    xml: { start: '<!--', end: ' -->' },
    markdown: { start: '<!--', end: ' -->' },
    vue: { start: '//', end: '' },
    clojure: { start: ';;', end: '' },
    lisp: { start: ';;', end: '' },
    erlang: { start: '%', end: '' },
    matlab: { start: '%', end: '' },
    latex: { start: '%', end: '' },
    // Everything C-family / curly-brace, plus the general default:
    // c, cpp, csharp, java, javascript, typescript, javascriptreact,
    // typescriptreact, go, rust, swift, kotlin, php, scala, dart, json (jsonc), etc.
};
function getCommentStyle(languageId) {
    const overrides = vscode.workspace
        .getConfiguration('commentBanner')
        .get('languageComments', {});
    if (overrides[languageId]) {
        return overrides[languageId];
    }
    if (DEFAULT_STYLES[languageId]) {
        return DEFAULT_STYLES[languageId];
    }
    return { start: '//', end: '' };
}
function getTargetWidth(document) {
    const config = vscode.workspace.getConfiguration('commentBanner', document.uri);
    const configured = config.get('lineLength', 0);
    if (configured && configured > 0) {
        return configured;
    }
    // Fall back to this file's first configured ruler, matching how Zed
    // reads "preferred_line_length" — VS Code's closest equivalent is
    // editor.rulers.
    const rulers = vscode.workspace
        .getConfiguration('editor', document.uri)
        .get('rulers', []);
    if (rulers.length > 0) {
        return rulers[0];
    }
    return 80;
}
function buildBanner(style, label, width, fillChar, padding) {
    const head = `${style.start}${padding}───${padding}${label}${padding}`;
    const tail = style.end;
    // Character count via Array.from to stay correct for multi-byte fill chars.
    const headLen = Array.from(head).length;
    const tailLen = Array.from(tail).length;
    const dashCount = Math.max(1, width - headLen - tailLen);
    return `${head}${fillChar.repeat(dashCount)}${tail}`;
}
// Strip an existing banner/comment on the line down to a plain label,
// so re-running the command on an already-bannered line just refreshes it
// instead of nesting comment markers.
function extractLabel(lineText, style) {
    let text = lineText.trim();
    if (text.length === 0) {
        return 'Section';
    }
    if (text.startsWith(style.start)) {
        text = text.slice(style.start.length);
    }
    if (style.end && text.endsWith(style.end.trim())) {
        text = text.slice(0, text.length - style.end.trim().length);
    }
    // Remove leading/trailing fill characters and whitespace, e.g.
    // "─── Generic strings ───" -> "Generic strings"
    text = text.replace(/^[\s─\-=#*_.]+/, '').replace(/[\s─\-=#*_.]+$/, '');
    return text.length > 0 ? text : 'Section';
}
function activate(context) {
    const disposable = vscode.commands.registerTextEditorCommand('commentBanner.insert', (textEditor, edit) => {
        const document = textEditor.document;
        const style = getCommentStyle(document.languageId);
        const width = getTargetWidth(document);
        const fillChar = vscode.workspace
            .getConfiguration('commentBanner')
            .get('fillChar', '─');
        const padding = vscode.workspace
            .getConfiguration('commentBanner')
            .get('padding', ' ');
        // Support multiple cursors: each empty selection uses its own line.
        for (const selection of textEditor.selections) {
            const line = document.lineAt(selection.active.line);
            const label = selection.isEmpty
                ? extractLabel(line.text, style)
                : document.getText(selection).trim() || extractLabel(line.text, style);
            const banner = buildBanner(style, label, width, fillChar, padding);
            edit.replace(line.range, banner);
        }
    });
    context.subscriptions.push(disposable);
}
function deactivate() { }
//# sourceMappingURL=extension.js.map