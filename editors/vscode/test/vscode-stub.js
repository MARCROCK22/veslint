'use strict';
// The part of the VS Code API the extension uses, enough to run it without the editor.
const fs = require('node:fs');

class Position {
  constructor(line, character) {
    this.line = line;
    this.character = character;
  }
  translate(lines, characters) {
    return new Position(this.line + lines, this.character + characters);
  }
  isAfter(other) {
    return this.line > other.line || (this.line === other.line && this.character > other.character);
  }
}
class Range {
  constructor(start, end) {
    this.start = start;
    this.end = end;
  }
}
class Diagnostic {
  constructor(range, message, severity) {
    this.range = range;
    this.message = message;
    this.severity = severity;
  }
}
class WorkspaceEdit {
  constructor() {
    this.edits = [];
  }
  replace(uri, range, text) {
    this.edits.push({ uri, range, text });
  }
  insert(uri, position, text) {
    this.edits.push({ uri, range: new Range(position, position), text });
  }
}
class CodeAction {
  constructor(title, kind) {
    this.title = title;
    this.kind = kind;
  }
}
class Kind {
  constructor(value) {
    this.value = value;
  }
  append(part) {
    return new Kind(`${this.value}.${part}`);
  }
  contains(other) {
    return other.value === this.value || other.value.startsWith(this.value + '.');
  }
}
class TextDocument {
  constructor(file, languageId = 'typescript') {
    this.uri = Uri.file(file);
    this.languageId = languageId;
    this.version = 1;
    this.isDirty = false;
    this.isClosed = false;
    this.text = fs.readFileSync(file, 'utf8').replace(/^﻿/, '');
  }
  getText() {
    return this.text;
  }
  get lines() {
    return this.text.split('\n');
  }
  positionAt(offset) {
    const before = this.text.slice(0, offset).split('\n');
    return new Position(before.length - 1, before[before.length - 1].length);
  }
  offsetAt(position) {
    return this.lines.slice(0, position.line).reduce((n, l) => n + l.length + 1, 0) + position.character;
  }
  validatePosition(position) {
    const line = Math.min(Math.max(position.line, 0), this.lines.length - 1);
    return new Position(line, Math.min(Math.max(position.character, 0), this.lines[line].length));
  }
  getWordRangeAtPosition(position) {
    const line = this.lines[position.line];
    const word = /\w+/g;
    for (let match; (match = word.exec(line)); ) {
      if (match.index <= position.character && position.character <= match.index + match[0].length) {
        return new Range(new Position(position.line, match.index), new Position(position.line, match.index + match[0].length));
      }
    }
    return undefined;
  }
  lineAt(line) {
    const text = this.lines[line];
    return {
      text,
      firstNonWhitespaceCharacterIndex: text.length - text.trimStart().length,
      range: new Range(new Position(line, 0), new Position(line, text.length)),
    };
  }
}
const Uri = {
  file: fsPath => ({ scheme: 'file', fsPath, toString: () => `file://${fsPath}` }),
  parse: value => ({ scheme: value.split(':')[0], value, toString: () => value }),
};

function create() {
  const state = {
    settings: {},
    folder: undefined,
    documents: [],
    diagnostics: new Map(),
    messages: [],
    output: [],
    handlers: {},
    commands: {},
    provider: undefined,
    status: {},
  };
  const event = name => handler => {
    state.handlers[name] = handler;
    return { dispose() {} };
  };
  const vscode = {
    Position,
    Range,
    Diagnostic,
    WorkspaceEdit,
    CodeAction,
    Uri,
    CodeActionKind: { QuickFix: new Kind('quickfix'), SourceFixAll: new Kind('source.fixAll') },
    DiagnosticSeverity: { Error: 0, Warning: 1, Information: 2, Hint: 3 },
    StatusBarAlignment: { Left: 1, Right: 2 },
    languages: {
      createDiagnosticCollection: () => ({
        set: (uri, list) => state.diagnostics.set(uri.toString(), list),
        delete: uri => state.diagnostics.delete(uri.toString()),
        dispose() {},
      }),
      registerCodeActionsProvider: (selector, provider) => {
        state.provider = provider;
        return { dispose() {} };
      },
    },
    window: {
      activeTextEditor: undefined,
      createOutputChannel: () => ({ appendLine: line => state.output.push(line), show() {}, dispose() {} }),
      createStatusBarItem: () => Object.assign(state.status, { show() {}, dispose() {} }),
      showWarningMessage: async message => void state.messages.push(message),
      showInformationMessage: async message => void state.messages.push(message),
    },
    workspace: {
      get textDocuments() {
        return state.documents;
      },
      // `state.defaults` are the defaults the editor has registered (those of the manifest when absent).
      getConfiguration: () => ({
        get: (name, fallback) => (name in state.settings ? state.settings[name] : state.defaults && name in state.defaults ? state.defaults[name] : fallback),
        inspect: name => ({ key: `veslint.${name}`, defaultValue: state.defaults?.[name], globalValue: state.settings[name] }),
      }),
      getWorkspaceFolder: () => (state.folder ? { uri: Uri.file(state.folder) } : undefined),
      onDidOpenTextDocument: event('open'),
      onDidSaveTextDocument: event('save'),
      onDidCloseTextDocument: event('close'),
      onDidChangeConfiguration: event('configuration'),
      onDidChangeTextDocument: event('change'),
      onDidChangeWorkspaceFolders: event('folders'),
      createFileSystemWatcher: pattern => {
        state.watched = [...(state.watched ?? []), pattern];
        const watcher = { dispose() {} };
        for (const name of ['onDidChange', 'onDidCreate', 'onDidDelete']) {
          watcher[name] = handler => {
            state.handlers[`${pattern}.${name}`] = handler;
            return { dispose() {} };
          };
        }
        return watcher;
      },
      applyEdit: async edit => {
        state.applied = edit;
        return true;
      },
    },
    commands: {
      registerCommand: (name, handler) => {
        state.commands[name] = handler;
        return { dispose() {} };
      },
      executeCommand: async () => undefined,
    },
  };
  return { vscode, state, TextDocument };
}

module.exports = { create };
