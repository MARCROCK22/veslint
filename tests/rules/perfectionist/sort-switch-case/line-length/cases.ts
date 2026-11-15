declare const value: string;
declare function log(text: string): void;
switch (value) {
  case 'k10':
  case 'k2':
  case 'k1':
    log('k');
    break;
  case 'bb':
    log('bb');
    break;
  case 'a':
    log('a');
    break;
  case 'ccc':
  default:
  case 'B':
    log('d');
    break;
}
switch (value) {
  case 'xx':
  case 'yy':
    break;
  case 'c':
    break;
  case 'b':
    break;
}
