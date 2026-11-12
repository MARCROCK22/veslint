// prefer-find: the suggestion replaces `filter` with `find` and removes the element access.
// Non-ASCII text before the ranges: ñ 😀 日本語.
declare const arr: number[];
declare const maybe: number[] | undefined;
declare const cond: boolean;
declare function pred(n: number): boolean;
const key = 'filter';

// `[0]` and `.at(0)`.
arr.filter(pred)[0];
arr.filter(pred).at(0);
arr.filter(pred)['0'];
arr.filter(pred)['at'](0);
arr.filter(pred).at(NaN);
// Between brackets `filter` becomes `"find"`.
arr['filter'](pred)[0];
arr[`filter`](pred).at(0);
arr[key](pred)[0];
arr[('filter')](pred)[0];
// Parentheses, comments and several lines: the removal starts at the first `.` or `[`.
(arr.filter(pred))[0];
(arr.filter(pred)).at(0);
((arr).filter(pred))[0];
arr.filter(pred) /* a */ [ /* b */ 0 /* c */ ];
(arr.filter(pred) /* a */) /* b */ . /* c */ at(0);
arr
  .filter(pred)
  .at(0);
// Both branches of a conditional and the last expression of a sequence.
(cond ? arr.filter(pred) : arr.filter(pred))[0];
(cond ? arr['filter'](pred) : arr.filter(pred)).at(0);
(1, arr.filter(pred))[0];
(cond, cond ? arr.filter(pred) : (0, arr.filter(pred)))[0];
// Optional chains and what follows the access.
maybe?.filter(pred)[0];
(maybe?.filter(pred))[0];
arr.filter(pred)[0].toFixed();
const withDefault = arr.filter(pred)[0] ?? 0;
// Non-ASCII text on the same line.
const ñ = '😀'; arr.filter(pred)[0]; const 日本 = arr.filter(pred).at(0);
