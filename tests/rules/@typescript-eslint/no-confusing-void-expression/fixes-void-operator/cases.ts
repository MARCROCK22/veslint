declare function log(...args: unknown[]): void;
declare const cond: boolean;
declare const obj: { run(): void; maybe?: { run(): void } };
declare function tag(strings: TemplateStringsArray): void;
declare function asyncVoid(): Promise<void>;

const a1 = () => log();
const a2 = () => (log());
const a3 = async () => await asyncVoid();
const a4 = () => obj.maybe?.run();
const a5 = () => tag`x`;
const a6 = () => cond && log();
const a7 = () => void log();
function r1() {
  return log();
}
function r2() {
  if (cond) return (obj).run();
  return /* c */ log();
}
const g1 = [log()];
const g2 = cond ? log() : 1;
const g3 = `${log()}`;
const g4 = void log();
log(log());
const g5 = (log(), 1);
const résumé = '🎉é'; const g6 = [log(), (log())];
void [a1, a2, a3, a4, a5, a6, a7, r1, r2, g1, g2, g3, g4, g5, g6, résumé];
