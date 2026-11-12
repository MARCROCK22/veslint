// Lines end with CRLF.
interface I1 {
  // before
  (): void; // after
}
export interface I2 {
  /* before */
  (a: string): void;
}
type T1 = {
  (): void
} | string;
