// The JSX pragma: the first element or fragment references the variable named like the pragma with
// the declared identifier itself, whose range takes its type annotation. That is no use before the
// definition, but a use of a name declared later still is.
declare const React: any;
export const element = <div />;
export const fragment = <></>;

export const early = laterValue;
const laterValue: number = 1;
