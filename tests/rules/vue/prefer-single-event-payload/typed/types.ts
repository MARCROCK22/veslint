export type Emits = {
  (e: 'click' | 'used', payload: string, extra: number): void
  (e: 'unusedTyped' | 'focus'): void
}
export interface ObjEmits { submit: [a: number]; objUnused: [] }
