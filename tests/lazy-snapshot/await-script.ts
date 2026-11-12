// A script that declares an `await` function: TypeScript reads `await (1)` as a call of it, before
// its definition, so the file is parsed again that way (and the snapshot made) to see it.
await (1);
function await(value: number): number {
  return value;
}
