// unicorn/require-array-join-separator: `.join()` without its separator.
declare const list: string[];
declare const like: ArrayLike<string>;

const j1 = list.join();
const j2 = [].join.call(like);
const j3 = [].join.call(like,);
const j4 = Array.prototype.join.call(like, );
const j5 = list?.join();
const j6 = list.join(
  // nothing
);

// Not reported.
const z1 = list.join(',');
const z2 = list.join?.();
const z3 = Array.prototype.join.call(like, '');
const z4 = list['join']();
