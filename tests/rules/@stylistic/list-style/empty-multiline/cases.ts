// `empty: "always"` and `multiLine.minItems: 1`: empty lists on several lines.
declare function log(...args: unknown[]): void;
export const array = [
];
export const object = {
};
export const object2 = {

};
export function foo(
) {}
log(
);
interface Empty {
}
type Literal = {
};
enum EmptyEnum {
}
export type { Empty, Literal };
export { EmptyEnum };
export const sameLine = {};
export const sameLine2 = { };
export const commented = { /* comment */
};
export const commented2 = {
  /* comment */ };
export const commented3 = {
  /* comment */
};
log(/* comment */
);
export const commented4 = { /* a */
  /* b */ };
import {
} from 'node:fs';
import {} from 'node:path' with {
};
import data from './data.json' with { };
export { data };
