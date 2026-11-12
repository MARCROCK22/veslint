interface Options {
  required: string;
}
declare const options: Options;

// The option silences the line 0 report.
const { required = 'x' } = options;

export { required };
