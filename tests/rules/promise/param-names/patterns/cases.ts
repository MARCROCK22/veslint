// promise/param-names with resolvePattern and rejectPattern (a `/` in the pattern is escaped in
// the message).
declare function run(...args: unknown[]): void;

new Promise((ok, fail) => run(ok, fail));
new Promise((yes, no) => run(yes, no));
new Promise((resolve, reject) => run(resolve, reject));
