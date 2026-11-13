declare const x: string;

// Reported.
setTimeout('alert(1)', 0);
setInterval('alert(1)', 0);
setTimeout(`alert(${x})`, 0);
setTimeout('a' + x, 0);
window.setTimeout('alert(1)', 0);
window.window.setInterval('alert(1)', 0);
globalThis.setTimeout('x');
const s = 'code';
setTimeout(s);

// Not reported.
setTimeout(() => {}, 0);
setTimeout(x, 0);
setTimeout();
function shadow(setTimeout: any) {
  setTimeout('x');
}
