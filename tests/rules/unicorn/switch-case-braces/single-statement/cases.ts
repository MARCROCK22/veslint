// unicorn/switch-case-braces with "single-statement": one statement per case clause, in braces
// only when it is a declaration that needs a block.
declare let a: number;
declare function f(n: number): void;

switch (a) {
  case 1:
    f(1);
  case 2:
    f(2);
    break;
  case 3: {
    f(3);
  }
  case 4: {
    f(4);
    break;
  }
  case 5:
    const x = 5;
  case 6: {
    const y = 6;
  }
  case 7:
    var z = 7;
    f(z);
  case 8:
    let w = 8;
    f(w);
  case 9: {}
  case 10: { // trailing
    f(10);
  }
  case 11: {
    f(11); // keep
  }
  case 12: {
    f(12);
  } // after
  case 13:
    f(13); // comment
    break;
  default:
}
