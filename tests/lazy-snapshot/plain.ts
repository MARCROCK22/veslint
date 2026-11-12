// No rule of the run needs types and nothing here asks for them: tsgo only parses the tsconfig.
// The awaits are in async bodies, where TypeScript always reads the operator.
export class Holder {
  method(): this {
    const self = this;
    return self;
  }
}

export async function load(values: Promise<number>[]): Promise<number[]> {
  const all = await (Promise.all(values));
  const first = await [all[0]][0];
  const arrow = async () => await (values[0]);
  return [...all, first, await arrow()];
}
