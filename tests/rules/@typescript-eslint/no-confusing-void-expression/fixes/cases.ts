declare function log(...args: unknown[]): void;
declare const cond: boolean;
declare const obj: { run(): void; maybe?: { run(): void } };
declare const list: number[];
declare function tag(strings: TemplateStringsArray): void;
declare function asyncVoid(): Promise<void>;

const a1 = () => log();
const a2 = () => (log());
const a3 = () => ((log()));
const a4 = () => /* c */ log();
const a5 = () => ( /* inner */ log() /* after */ );
const a6 = async () => await asyncVoid();
const a7 = () => obj.maybe?.run();
const a8 = () => cond && log();
const a9 = () => (cond ? log() : log(1));
const a10 = () => tag`x`;
const a11 = () => (log(), log(1));
list.forEach(x => log(x));
list.forEach((x) => (log(x)));
const a12 = () =>
  log(
    1,
  );
const a13 = () => (cond ? log() : undefined);
const a14 = (): void => log();

function r1() {
  return log();
}
function r2() {
  if (cond) {
    return log();
  }
  log();
}
function r3() {
  if (cond) return log();
  log();
}
function r4() {
  return (log());
}
function r5() {
  return [1].forEach(x => log(x));
}
function r6() {
  return (cond ? obj : obj).run();
}
function r7() {
  log()
  return log()
}
function r8() {
  return cond && log();
}
function r9() {
  if (cond) {
    return cond && log();
  }
  log();
}
function r10() {
  switch (cond) {
    case true:
      return log();
    default:
      return (log());
  }
}
function r11() {
  return /* c */ log() /* d */;
}
const r12 = function () {
  return log();
};
const r13 = () => {
  return log();
};
class K {
  m() {
    return log();
  }
  n() {
    if (cond) return (obj).run();
    else return [log][0]();
  }
}
function r14() {
  label: return log();
}
function r15() {
  if (cond) {
    return (obj.maybe)?.run();
  }
  return tag`x`;
}
async function r16() {
  if (cond) {
    return await asyncVoid();
  }
  return await asyncVoid();
}
const g1 = [log()];
const g2 = `${log()}`;
const résumé = '🎉é'; const a15 = () => log();
void [a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, g1, g2, résumé];
void [r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15, r16, K];
