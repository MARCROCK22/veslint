// A script: outside an async function, TypeScript reads `await` before a template as a tag.
declare function await(strings: TemplateStringsArray, ...values: unknown[]): string;
function notAsync(): string {
  return await`${'a'}`;
}
const plain = `${'b'}x`;
// What follows belongs to the same expression: the template is still tagged.
function chains(): unknown {
  return [await`${'c'}`.length, await`${'d'}`[0], await`${'e'}`.concat(`${'f'}`), await (`${'g'}`).length];
}
async function asyncChains(): Promise<unknown> {
  return [await `${'h'}`.length, await (`${'i'}`).length];
}
void [chains, asyncChains];
