// An enum declared in another file of the project.
export enum Remote {
  First = 1,
  'second one' = 2,
}

// Computed member names: typescript-estree rejects them in a linted file.
export enum Computed {
  ['key one'] = 'one',
  [ /* inner */ "two" ] = 'two',
}
