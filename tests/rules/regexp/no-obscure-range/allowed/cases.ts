// Reported (allowed: alphanumeric and !-/).
export const a1 = /[ -~]/;
export const a2 = /[:-@]/;
// Not reported.
export const b1 = /[!-$]/;
export const b2 = /[a-z]/;
