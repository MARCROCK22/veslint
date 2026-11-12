export {};
declare const code: string;

// Shadowed names are not the globals.
function shadowTimeout(): void {
  function setTimeout(callback: string): void {}
  setTimeout(code);
  window.setTimeout(code);
}
function shadowLater(): void {
  window.setTimeout(code);
  const setTimeout = (callback: string): void => {};
  setTimeout(code);
}
function shadowFunction(): void {
  class Function {
    constructor(body: string) {}
  }
  new Function('return 1');
}
function unrelated(): void {
  const setInterval = 1;
  window.setTimeout(code);
}
{
  const setTimeout = (callback: string): void => {};
  setTimeout(code);
}
setTimeout(code);
