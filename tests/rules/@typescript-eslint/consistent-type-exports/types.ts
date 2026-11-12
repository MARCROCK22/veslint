export type T1 = string;
export interface I1 {
  a: number;
}
type Hidden = number;
export type { Hidden as Renamed };
