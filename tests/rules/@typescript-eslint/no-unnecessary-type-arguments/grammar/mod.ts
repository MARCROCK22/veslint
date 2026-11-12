export class Box<T = string> {
  value?: T;
}
export function generic<T = string>(x?: T): T | undefined {
  return x;
}
