declare const a: boolean;

// Reported.
debugger;
if (a) debugger;
function f() {
  debugger;
}

// Not reported.
const debuggerName = 'debugger';
