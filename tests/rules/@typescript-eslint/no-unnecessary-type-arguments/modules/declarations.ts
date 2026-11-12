export interface Remote<T = string> {
  value: T;
}
export class RemoteBox<T = number> {
  value?: T;
}
export function remote<T = boolean>(value?: T): T | undefined {
  return value;
}
export default interface Fallback<T = bigint> {
  value: T;
}
