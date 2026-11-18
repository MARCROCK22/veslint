declare function $derived<T>(value: T): T;
let a = 1;
let b = $derived(1);
let c = [1];
export { a, b, c };
