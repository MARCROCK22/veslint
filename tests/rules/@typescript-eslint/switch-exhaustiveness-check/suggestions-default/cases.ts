declare const text: string;
declare const mixed: 'a' | 'b' | number;
declare const count: number;
declare function run(): void;

switch (text) {
  case 'a':
    break;
}
switch (text) {
}
switch (mixed) {
  case 'a':
    break;
}
switch (mixed) {
}
function nested(value: number) {
  switch (value) {
    case 1:
      run() // trailing
  }
}
switch (count) { case 1: break; /* 🎉 */ case 2: }
switch (text) {
  case 'a':
    break;
  default:
    break;
}
switch (text) {
  case 'a':
    break;
  // no default
}
void nested;
