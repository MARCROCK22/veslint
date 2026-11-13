declare const name: string;

// Reported.
const a1 = 'Hello ${name}';
const a2 = "${a} and ${b}";
const a3 = 'x ${ } ${y}';

// Not reported.
const k1 = `Hello ${name}`;
const k2 = 'Hello {name}';
const k3 = '${}';
const k4 = '$ {name}';
