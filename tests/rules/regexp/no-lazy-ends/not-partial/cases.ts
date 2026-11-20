// Reported (ignorePartial: false): whatever the use.
export const a1 = /a+?/;
export const a2 = /a+?/.source;
export const a3 = /(?:b|c??)/;
// Not reported.
export const b1 = /a+?b/;
