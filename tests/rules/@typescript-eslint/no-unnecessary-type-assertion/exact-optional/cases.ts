interface Options {
  value?: string;
  other?: string | undefined;
}
declare const options: Options;
declare const maybe: string | undefined;

// With exactOptionalPropertyTypes, the parts other than undefined decide.
const a = options.value as string | undefined;
const b = maybe as string | undefined;
const c = options.other as string | undefined;

export { a, b, c };
