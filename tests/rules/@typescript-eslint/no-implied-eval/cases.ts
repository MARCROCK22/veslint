export {};
declare const code: string;
declare const handler: () => void;
declare const maybeHandler: (() => void) | string;
declare const anyValue: any;
declare function makeHandler(): () => void;
declare function makeCode(): string;
declare const obj: { method(): void; prop: string };
declare const fnObject: Function;
declare function execScript(code: string): void;
declare function setImmediate(callback: string | (() => void)): void;
declare const global: typeof globalThis;
class Holder {
  method(): void {}
}
const holder = new Holder();

// Strings and other non-functions as handlers.
setTimeout('alert(1)');
setTimeout(`alert(${code})`, 100);
setTimeout(code);
setInterval(code, 10);
setTimeout(makeCode());
setTimeout(obj.prop);
setTimeout(maybeHandler);
setTimeout(1);
setTimeout(null);
setTimeout(anyValue);
window.setTimeout(code);
window['setInterval'](code);
globalThis.setTimeout(code);
global.setTimeout(code);
window.setTimeout?.(code);
(setTimeout)(code);
execScript(code);
setImmediate(code);
setTimeout(...[code]);
new setTimeout(code);

// Functions as handlers.
setTimeout(() => {});
setTimeout(function () {});
setTimeout(handler);
setTimeout(makeHandler());
setTimeout(handler.bind(null));
setTimeout(obj.method);
setTimeout(holder.method);
setTimeout(fnObject);
setTimeout((handler));
setTimeout();
window.unknownTimer(code);
other.setTimeout(code);

// The Function constructor.
new Function('return 1');
Function('return 1');
window.Function('return 1');
const created = new globalThis.Function('a', 'return a');
