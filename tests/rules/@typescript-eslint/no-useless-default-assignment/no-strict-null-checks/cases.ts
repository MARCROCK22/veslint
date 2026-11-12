interface Options {
  required: string;
}
declare const options: Options;

// Without strictNullChecks the rule reports at line 0.
const { required = 'x' } = options;

export { required };
