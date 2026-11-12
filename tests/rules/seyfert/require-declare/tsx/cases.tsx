import { Command, Declare } from 'seyfert';

// A .tsx file.
export class InTsx extends Command {}
@Declare({ name: 'tsx', description: 'tsx' })
export class DeclaredInTsx extends Command {}
export const identity = <T,>(value: T) => value;
