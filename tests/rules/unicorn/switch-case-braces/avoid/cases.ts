// unicorn/switch-case-braces: a case clause with statements has them in braces ("always"), or
// without braces when nothing it declares needs them ("avoid", in avoid/). Empty braces are
// reported with both.
declare let a: number;
declare function f(n: number): void;

switch (a) {
  case 1:
    f(1);
    break;
  case 2: {
    f(2);
    break;
  }
  case 3: {
    const x = 3;
    f(x);
    break;
  }
  case 4: {
    function g(): void {}
    g();
    break;
  }
  case (5): f(5);
  case 6 as number:
  case 7: {}
  case 8:
    {
      f(8);
    }
    f(8);
  default:
    f(0);
}
switch (a) {
  case 1: {
  }
  default: {
    // only a comment
  }
}
switch (a) {
  case 1:
  case 2:
}

// 79.0.0: blocks with declarations that need them are kept; comments in the block.
switch (a) {
  case 30: {
    class C {}
    f(30);
  }
  case 31: {
    type T = number;
    f(31);
  }
  case 32: {
    var v = 32;
  }
  case 33: {
    f(33); // keep
  }
  case 34: {
    f(34);
  } // after
  case 35: {
    f(35);
    // last
  }
  case 36: {
    f(36);
    // last
  } f(37);
}
