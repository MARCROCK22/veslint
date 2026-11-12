// The exports inside a module declaration are not looked at (its body is not a list).
declare module 'm' {
  export const a: number;
  export {};
}
export {};
