// The locale of the project, registered in seyfert's registry as its own projects do.
export const en = {
  greeting: 'hi',
  farewell: 'bye',
  nested: { deep: 'x', count: (n: number) => `${n}` },
};

declare module 'seyfert' {
  interface SeyfertRegistry {
    langs: typeof en;
  }
}
