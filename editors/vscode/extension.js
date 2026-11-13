'use strict';
// veslint for VS Code: runs the veslint binary on the TypeScript files of the workspace and shows
// what it reports as diagnostics, with its fixes and suggestions as quick fixes.
//
// Each workspace folder has a `veslint --server` (lib/server.js) that keeps the TypeScript compiler
// and the project between lints, and is given the text of files with unsaved changes; the files
// that change on disk are told to it with the next request. A veslint without the server mode is
// run once per lint instead, and then only saved text is linted. The fixes of a run are offered
// only until the text changes. The configuration ESLint resolves for each file is asked once and
// kept until a configuration file changes (lib/configCache.js).
const vscode = require('vscode');
const path = require('node:path');
const { runVeslint, findConfig, isTypeScriptPath } = require('./lib/runner');
const { ConfigCache } = require('./lib/configCache');
const { VeslintServer, ServerError } = require('./lib/server');
const { parseOutput, parseStderr, ruleDocumentation } = require('./lib/parse');

const selector = [
  { language: 'typescript', scheme: 'file' },
  { language: 'typescriptreact', scheme: 'file' },
];
const fixAllKind = vscode.CodeActionKind.SourceFixAll.append('veslint');
const severities = {
  error: vscode.DiagnosticSeverity.Error,
  warning: vscode.DiagnosticSeverity.Warning,
  information: vscode.DiagnosticSeverity.Information,
  hint: vscode.DiagnosticSeverity.Hint,
};

/** @type {vscode.DiagnosticCollection} */
let diagnostics;
/** @type {vscode.OutputChannel} */
let output;
/** @type {vscode.StatusBarItem} */
let status;
/** @type {ConfigCache} */
let cache;
/** The server of each workspace folder. */
const servers = new Map();
/** The binaries that have no server mode (an older veslint). */
const unsupported = new Set();
/** What changed on disk in each folder since its server was last told. */
const changes = new Map();
/** The pending lint of each file while it is being typed. */
const typing = new Map();
/** What the last run said of each file: the version of the text it was for, and its problems. */
const linted = new Map();
/** The run of each file that has not finished, to stop it when a newer one starts. */
const running = new Map();
/**
 * Lints go one at a time until their request is sent, and their answers are awaited out of it: a
 * server answers in order, and gives up a request that a later one for the same file made useless.
 */
let queue = Promise.resolve();
/** Settles once every lint started so far has ended (what `lint` gives back). */
let settled = Promise.resolve();
const told = new Set();

/**
 * When files are linted. Only a value that was set counts: after an update without a reload of the
 * window, VS Code keeps the settings of the version it loaded first (it tells the contributions of
 * an extension apart by its identifier), and before 0.3.0 the default was `onSave`.
 */
function runSetting(config) {
  const info = config.inspect('run');
  const values = [info?.globalValue, info?.workspaceValue, info?.workspaceFolderValue, info?.globalLanguageValue, info?.workspaceLanguageValue, info?.workspaceFolderLanguageValue];
  return values.some(value => value !== undefined) ? config.get('run') : 'onType';
}

/**
 * How long typing must pause before a file is linted (`onType`), in milliseconds: 0 (the default)
 * lints after every change. What is not a number of 0 or more counts as 0.
 */
function delaySetting(config) {
  const value = Number(config.get('typingDelay', 0));
  return Number.isFinite(value) && value > 0 ? Math.min(value, 2 ** 31 - 1) : 0;
}

function settings(uri) {
  const config = vscode.workspace.getConfiguration('veslint', uri);
  return {
    enable: config.get('enable', true),
    binary: config.get('path', 'veslint') || 'veslint',
    config: config.get('config', ''),
    project: config.get('project', ''),
    run: runSetting(config),
    typingDelay: delaySetting(config),
    severity: severities[config.get('severity', 'warning')] ?? vscode.DiagnosticSeverity.Warning,
    timeout: config.get('timeout', 120000),
  };
}

/** The directory veslint runs in for a file: its workspace folder, or its own directory. */
function folderOf(uri) {
  return vscode.workspace.getWorkspaceFolder(uri)?.uri.fsPath ?? path.dirname(uri.fsPath);
}

/** A path of the settings: relative to the folder when it has a directory and is not absolute. */
function resolveSetting(folder, value) {
  if (value === '' || path.isAbsolute(value) || !/[\\/]/.test(value)) return value;
  return path.join(folder, value);
}

function tellOnce(key, message, ...actions) {
  if (told.has(key)) return;
  told.add(key);
  vscode.window.showWarningMessage(message, ...actions).then(choice => {
    if (choice === 'Open Settings') vscode.commands.executeCommand('workbench.action.openSettings', 'veslint');
    if (choice === 'Show Output') output.show(true);
  });
}

function setStatus(icon, tooltip) {
  status.text = `$(${icon}) veslint`;
  status.tooltip = tooltip;
  status.show();
}

/**
 * The range of a problem: from where it starts to where it ends, as ESLint's; without an end (or
 * with an empty range), the word where it starts.
 */
function problemRange(document, problem) {
  const start = document.validatePosition(new vscode.Position(problem.line - 1, problem.column - 1));
  if (problem.endLine != null) {
    const end = document.validatePosition(new vscode.Position(problem.endLine - 1, problem.endColumn - 1));
    if (end.isAfter(start)) return new vscode.Range(start, end);
  }
  const word = document.getWordRangeAtPosition(start);
  if (word && word.end.isAfter(start)) return new vscode.Range(start, word.end);
  const end = document.validatePosition(start.translate(0, 1));
  return new vscode.Range(start, end);
}

function problemSeverity(problem, fallback) {
  if (problem.rule !== 'eslint') return fallback;
  return problem.messageId === 'warning' ? vscode.DiagnosticSeverity.Warning : vscode.DiagnosticSeverity.Error;
}

function toDiagnostic(document, problem, severity) {
  const diagnostic = new vscode.Diagnostic(problemRange(document, problem), problem.message, problemSeverity(problem, severity));
  diagnostic.source = 'veslint';
  const documentation = ruleDocumentation(problem.rule);
  diagnostic.code = documentation
    ? { value: problem.rule, target: vscode.Uri.parse(documentation) }
    : problem.rule;
  return diagnostic;
}

/** Whether a file is one veslint lints here: TypeScript, on disk, and not turned off. */
function lintable(document) {
  return document.uri.scheme === 'file' && isTypeScriptPath(document.uri.fsPath) && settings(document.uri).enable;
}

/** The changes on disk of a folder that its server has not been told yet. */
function changesOf(folder) {
  let pending = changes.get(folder);
  if (!pending) {
    pending = { changed: new Set(), created: new Set(), deleted: new Set(), forget: new Set(), reset: false };
    changes.set(folder, pending);
  }
  return pending;
}

function noteChange(uri, kind) {
  if (uri.scheme !== 'file') return;
  const pending = changesOf(folderOf(uri));
  if (kind === 'reset') pending.reset = true;
  else pending[kind].add(uri.fsPath);
}

/** Takes the changes of a folder for a request. */
function takeChanges(folder) {
  const pending = changesOf(folder);
  changes.delete(folder);
  return {
    changed: [...pending.changed],
    created: [...pending.created],
    deleted: [...pending.deleted],
    forget: [...pending.forget],
    reset: pending.reset,
  };
}

function stopServers() {
  for (const server of servers.values()) server.stop();
  servers.clear();
  changes.clear();
}

/**
 * Lints a request through the server of its folder: what the command line would give, or null
 * for a veslint without the server mode. A server that fails gives that error, and the next lint
 * starts another one; a binary that cannot be run throws.
 */
async function lintThroughServer(folder, binary, options, request) {
  if (unsupported.has(binary)) return null;
  let server = servers.get(folder);
  if (!server || server.binary !== binary) {
    server?.stop();
    server = new VeslintServer(binary, folder, { timeout: options.timeout });
    servers.set(folder, server);
  }
  try {
    const answer = await server.request(request);
    // Given up for a later request of the same file, whose answer is the one to show.
    if (answer.cancelled) return { cancelled: true };
    return { code: answer.code, problems: parseOutput(answer.stdout), ...parseStderr(answer.stderr), cancelled: false };
  } catch (error) {
    if (servers.get(folder) === server) servers.delete(folder);
    server.stop();
    if (!(error instanceof ServerError)) throw error;
    if (error.code === 'STOPPED') return { cancelled: true };
    if (error.code === 'UNSUPPORTED') {
      unsupported.add(binary);
      output.appendLine(`${binary} has no server mode: every lint runs it again, and only saved text is linted`);
      return null;
    }
    return { code: 2, problems: [], warnings: [], errors: [error.message], summary: '', cancelled: false };
  }
}

/**
 * Lints a document. With a server, a document with unsaved changes is linted with its text;
 * without one, only as it is on disk. What it gives back settles once every lint started so far
 * has ended.
 */
function lint(document, manual = false) {
  if (!lintable(document)) return settled;
  const binary = resolveSetting(folderOf(document.uri), settings(document.uri).binary);
  if (document.isDirty && unsupported.has(binary)) {
    if (manual) vscode.window.showInformationMessage('This veslint has no server mode: it lints the file on disk, so save it first.');
    return settled;
  }
  const key = document.uri.toString();
  running.get(key)?.abort();
  const controller = new AbortController();
  running.set(key, controller);
  // The queue goes on once the request is sent: `sent` holds the end of the lint in an object, so
  // that the queue does not wait for it.
  const sent = queue.then(() => lintNow(document, controller));
  queue = sent.then(
    () => {},
    () => {},
  );
  const done = sent.then(turn => turn?.done).catch(error => output.appendLine(`veslint: ${error?.stack ?? error}`));
  settled = Promise.all([settled, done]).then(() => {});
  return settled;
}

/**
 * The turn of a lint in the queue: it resolves the configuration and sends the request, and gives
 * back the end of the lint (`done`), awaited out of the queue so that the next lint does not wait
 * for this one's answer (the server gives this one up when the next one lints the same file).
 * Without a server, the whole lint happens in its turn.
 */
async function lintNow(document, controller) {
  const key = document.uri.toString();
  if (controller.signal.aborted || document.isClosed) return;
  const options = settings(document.uri);
  const folder = folderOf(document.uri);
  const config = findConfig(folder, options.config);
  if (!config) {
    diagnostics.delete(document.uri);
    linted.delete(key);
    setStatus('circle-slash', `No configuration for ${folder}: set veslint.config or add an eslint.config file`);
    return;
  }
  const file = document.uri.fsPath;
  const binary = resolveSetting(folder, options.binary);
  setStatus('sync~spin', `Linting ${path.basename(file)}`);
  const started = Date.now();
  const cannotRun = error => {
    if (running.get(key) === controller) running.delete(key);
    setStatus('error', `Cannot run ${options.binary}`);
    output.appendLine(`cannot run ${options.binary}: ${error.message}`);
    tellOnce('binary', `veslint: cannot run \`${options.binary}\` (${error.code ?? error.message}). Set "veslint.path" to the veslint binary.`, 'Open Settings');
  };
  let resolution;
  try {
    // The open files of this folder that have no resolved configuration yet get it now too:
    // ESLint starts once for all of them.
    const others = vscode.workspace.textDocuments
      .filter(other => other !== document && lintable(other) && folderOf(other.uri) === folder)
      .map(other => other.uri.fsPath)
      .filter(other => !cache.has(other, config));
    resolution = await cache.configsFor({ binary, cwd: folder, config, files: [file, ...others], timeout: options.timeout, signal: controller.signal });
  } catch (error) {
    cannotRun(error);
    return;
  }
  if (resolution.resolved > 0) {
    output.appendLine(`resolved the configuration of ${resolution.resolved} files in ${((Date.now() - started) / 1000).toFixed(2)} s (${path.basename(config)})`);
  }
  for (const error of resolution.errors) output.appendLine(`  configuration: ${error}`);
  if (controller.signal.aborted) {
    if (running.get(key) === controller) running.delete(key);
    return;
  }
  const lintConfig = resolution.configs.get(file) ?? config;
  const project = resolveSetting(folder, options.project) || undefined;
  // The text and its version are taken together: the problems are about that text.
  const dirty = document.isDirty;
  const version = document.version;
  const request = {
    config: lintConfig,
    project: project ?? '',
    files: [file],
    texts: dirty ? { [file]: document.getText() } : {},
    fixes: true,
    ...takeChanges(folder),
  };
  const finish = async answer => {
    let result;
    try {
      result = await answer;
      if (!result) {
        if (dirty) {
          if (running.get(key) === controller) running.delete(key);
          setStatus('circle-slash', 'Save the file to lint it: this veslint has no server mode');
          return;
        }
        result = await runVeslint({ binary, cwd: folder, config: lintConfig, files: [file], project, timeout: options.timeout, signal: controller.signal });
      }
      if (controller.signal.aborted) {
        if (running.get(key) === controller) running.delete(key);
        return;
      }
    } catch (error) {
      cannotRun(error);
      return;
    }
    if (running.get(key) === controller) running.delete(key);
    if (result.cancelled) return;
    const seconds = ((Date.now() - started) / 1000).toFixed(2);
    output.appendLine(`${path.relative(folder, file)}: ${result.problems.length} problems in ${seconds} s (${path.basename(config)})`);
    for (const warning of result.warnings) output.appendLine(`  warning: ${warning}`);
    if (result.errors.length > 0) {
      for (const error of result.errors) output.appendLine(`  error: ${error}`);
      setStatus('error', result.errors[0]);
      tellOnce(`error:${result.errors[0]}`, `veslint: ${result.errors[0].split('\n')[0]}`, 'Show Output');
      return;
    }
    // Only the problems of this file: the paths veslint prints are relative to the folder.
    const mine = result.problems.filter(problem => path.resolve(folder, problem.path) === file);
    if (document.version !== version || document.isClosed) {
      // The text changed while it was linted: the lint of the new text will show its problems, and
      // until then the last ones stay.
      setStatus('check', result.summary || `${mine.length} problems`);
      return;
    }
    linted.set(key, { version, problems: mine });
    diagnostics.set(document.uri, mine.map(problem => toDiagnostic(document, problem, options.severity)));
    setStatus(mine.length > 0 ? 'warning' : 'check', result.summary || `${mine.length} problems`);
  };
  // A veslint without the server mode runs once for each lint, one at a time.
  if (unsupported.has(binary)) {
    await finish(null);
    return;
  }
  return { done: finish(lintThroughServer(folder, binary, options, request)) };
}

/** The problems of the last run that are still about the text of the document. */
function currentProblems(document) {
  const state = linted.get(document.uri.toString());
  return state && state.version === document.version ? state.problems : [];
}

function replaceEdit(document, change) {
  const edit = new vscode.WorkspaceEdit();
  edit.replace(document.uri, new vscode.Range(document.positionAt(change.start), document.positionAt(change.end)), change.text);
  return edit;
}

/** One edit with every fix that does not overlap an earlier one, as ESLint applies them. */
function fixAllEdit(document) {
  const fixes = currentProblems(document)
    .filter(problem => problem.fix)
    .map(problem => problem.fix)
    .sort((a, b) => a.start - b.start || a.end - b.end);
  const edit = new vscode.WorkspaceEdit();
  let last = -Infinity;
  let count = 0;
  for (const fix of fixes) {
    // ESLint's rule: a fix that starts at or before the end of the last one waits for another pass.
    if (last >= fix.start || fix.start > fix.end) continue;
    edit.replace(document.uri, new vscode.Range(document.positionAt(fix.start), document.positionAt(fix.end)), fix.text);
    last = fix.end;
    count++;
  }
  return count > 0 ? edit : null;
}

const codeActions = {
  provideCodeActions(document, range, context) {
    const actions = [];
    const problems = currentProblems(document);
    if (context.only?.contains(vscode.CodeActionKind.SourceFixAll) || context.only?.contains(fixAllKind)) {
      const edit = fixAllEdit(document);
      if (!edit) return [];
      const action = new vscode.CodeAction('Fix all veslint problems that have a fix', fixAllKind);
      action.edit = edit;
      return [action];
    }
    for (const diagnostic of context.diagnostics) {
      if (diagnostic.source !== 'veslint') continue;
      const problem = problems.find(
        candidate =>
          candidate.line - 1 === diagnostic.range.start.line &&
          candidate.column - 1 === diagnostic.range.start.character &&
          candidate.message === diagnostic.message,
      );
      if (!problem) continue;
      if (problem.fix) {
        const action = new vscode.CodeAction(`Fix this ${problem.rule} problem`, vscode.CodeActionKind.QuickFix);
        action.edit = replaceEdit(document, problem.fix);
        action.diagnostics = [diagnostic];
        action.isPreferred = true;
        actions.push(action);
      }
      for (const suggestion of problem.suggestions) {
        const action = new vscode.CodeAction(suggestion.message, vscode.CodeActionKind.QuickFix);
        action.edit = replaceEdit(document, suggestion);
        action.diagnostics = [diagnostic];
        actions.push(action);
      }
      if (problem.rule !== 'eslint') {
        const line = document.lineAt(diagnostic.range.start.line);
        const indent = line.text.slice(0, line.firstNonWhitespaceCharacterIndex);
        const action = new vscode.CodeAction(`Disable ${problem.rule} for this line`, vscode.CodeActionKind.QuickFix);
        action.edit = new vscode.WorkspaceEdit();
        action.edit.insert(document.uri, line.range.start, `${indent}// eslint-disable-next-line ${problem.rule}\n`);
        action.diagnostics = [diagnostic];
        actions.push(action);
      }
    }
    return actions;
  },
};

/** Forgets the resolved configurations and lints the open files again. */
function reloadConfiguration(always) {
  cache.clear();
  for (const document of vscode.workspace.textDocuments) {
    if (always || settings(document.uri).run !== 'manual') lint(document);
  }
  return settled;
}

function activate(context) {
  cache = new ConfigCache(path.join(context.globalStorageUri.fsPath, 'resolved'));
  diagnostics = vscode.languages.createDiagnosticCollection('veslint');
  output = vscode.window.createOutputChannel('veslint');
  status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 0);
  status.command = 'veslint.showOutput';
  const registered = vscode.workspace.getConfiguration('veslint').inspect('run')?.defaultValue;
  if (registered !== undefined && registered !== 'onType') {
    output.appendLine(`VS Code has the settings of an older veslint (veslint.run defaults to ${registered} there): reload the window to see the new ones. Files are linted while typing unless veslint.run is set.`);
  }
  const automatic = document => {
    if (settings(document.uri).run !== 'manual') lint(document);
  };
  context.subscriptions.push(
    diagnostics,
    output,
    status,
    vscode.workspace.onDidOpenTextDocument(automatic),
    vscode.workspace.onDidSaveTextDocument(document => {
      // The server reads it from disk again, not a text it was given before.
      noteChange(document.uri, 'forget');
      noteChange(document.uri, 'changed');
      automatic(document);
    }),
    vscode.workspace.onDidChangeTextDocument(event => {
      const document = event.document;
      if (!lintable(document)) return;
      // Back to the text on disk (undone or reverted): the server forgets the text it was given.
      if (!document.isDirty) noteChange(document.uri, 'forget');
      const options = settings(document.uri);
      if (event.contentChanges.length === 0 || options.run !== 'onType') return;
      // With no delay the lint still waits for the changes of the same moment (a paste, several
      // cursors) to arrive; a lint that has not started when the text changes again is skipped.
      const key = document.uri.toString();
      clearTimeout(typing.get(key));
      typing.set(
        key,
        setTimeout(() => {
          typing.delete(key);
          if (!document.isClosed) lint(document);
        }, options.typingDelay),
      );
    }),
    vscode.workspace.onDidCloseTextDocument(document => {
      const key = document.uri.toString();
      clearTimeout(typing.get(key));
      typing.delete(key);
      running.get(key)?.abort();
      running.delete(key);
      linted.delete(key);
      diagnostics.delete(document.uri);
      // Closed without saving: the server reads the file from disk again.
      if (lintable(document)) noteChange(document.uri, 'forget');
    }),
    vscode.workspace.onDidChangeWorkspaceFolders(event => {
      for (const removed of event.removed) {
        servers.get(removed.uri.fsPath)?.stop();
        servers.delete(removed.uri.fsPath);
        changes.delete(removed.uri.fsPath);
      }
    }),
    vscode.workspace.onDidChangeConfiguration(event => {
      if (!event.affectsConfiguration('veslint')) return;
      told.clear();
      cache.clear();
      stopServers();
      unsupported.clear();
      for (const document of vscode.workspace.textDocuments) {
        if (lintable(document)) automatic(document);
        else diagnostics.delete(document.uri);
      }
    }),
    vscode.languages.registerCodeActionsProvider(selector, codeActions, {
      providedCodeActionKinds: [vscode.CodeActionKind.QuickFix, fixAllKind],
    }),
    vscode.commands.registerCommand('veslint.lintFile', () => {
      const document = vscode.window.activeTextEditor?.document;
      if (document) return lint(document, true);
    }),
    vscode.commands.registerCommand('veslint.lintOpenFiles', () => {
      for (const document of vscode.workspace.textDocuments) lint(document);
      return settled;
    }),
    vscode.commands.registerCommand('veslint.fixFile', async () => {
      const document = vscode.window.activeTextEditor?.document;
      if (!document) return;
      const edit = fixAllEdit(document);
      if (edit) await vscode.workspace.applyEdit(edit);
      else vscode.window.showInformationMessage('veslint: no fix to apply. The fixes are those of the last lint, until the text changes: lint the file again to get them.');
    }),
    vscode.commands.registerCommand('veslint.showOutput', () => output.show(true)),
    vscode.commands.registerCommand('veslint.reloadConfiguration', () => reloadConfiguration(true)),
  );
  // A configuration file that changes, appears or goes: the resolved copies may be wrong.
  const configWatcher = vscode.workspace.createFileSystemWatcher('**/eslint.config.{js,mjs,cjs,ts,mts,cts}');
  for (const on of [configWatcher.onDidChange, configWatcher.onDidCreate, configWatcher.onDidDelete]) {
    context.subscriptions.push(on.call(configWatcher, () => reloadConfiguration(false)));
  }
  // TypeScript files that change on disk (saved here, or by another program): the servers read
  // them again. A tsconfig.json or a package that changes: they read everything again.
  const sourceWatcher = vscode.workspace.createFileSystemWatcher('**/*.{ts,mts,cts,tsx}');
  context.subscriptions.push(
    sourceWatcher.onDidChange(uri => noteChange(uri, 'changed')),
    sourceWatcher.onDidCreate(uri => noteChange(uri, 'created')),
    sourceWatcher.onDidDelete(uri => noteChange(uri, 'deleted')),
  );
  const projectWatcher = vscode.workspace.createFileSystemWatcher('**/{tsconfig*.json,package.json}');
  for (const on of [projectWatcher.onDidChange, projectWatcher.onDidCreate, projectWatcher.onDidDelete]) {
    context.subscriptions.push(on.call(projectWatcher, uri => noteChange(uri, 'reset')));
  }
  context.subscriptions.push(configWatcher, sourceWatcher, projectWatcher);
  for (const document of vscode.workspace.textDocuments) automatic(document);
}

function deactivate() {
  for (const controller of running.values()) controller.abort();
  running.clear();
  for (const timer of typing.values()) clearTimeout(timer);
  typing.clear();
  stopServers();
}

module.exports = { activate, deactivate };
