// Members named `in` or `instanceof` at the start of a line, without `;` before them, as Prisma
// writes its types: the grammar reads a member, not the operator.
export type Filter = {
  equals?: string
  in?: string[]
  notIn?: string[]
  instanceof: number[]
}
export interface Methods {
  a: string
  in(x: number[]): void
  b: string
  in<T>(x: T[]): T
}
export class Fields {
  a: string[] = []
  b: boolean
  in?: string[]
  c: number
  instanceof(): number[] {
    return []
  }
}
