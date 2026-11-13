declare const a: boolean;
declare const b: boolean;

// Reported.
function f1() {
  if (a) {
    return 1;
  } else {
    return 2;
  }
}
function f2() {
  if (a) return 1;
  else return 2;
}
function f3() {
  if (a) {
    return 1;
  } else if (b) {
    return 2;
  } else {
    return 3;
  }
}
function f4() {
  if (a) {
    if (b) {
      return 1;
    } else {
      return 2;
    }
  } else {
    const x = 3;
    return x;
  }
}
function f5() {
  if (a) {
    return 1;
  } else {
    let x = 1;
    return x;
  }
}
function f6(x: number) {
  if (a) {
    return 1;
  } else {
    const x = 2;
    return x;
  }
}
function f7() {
  const x = 1;
  if (a) {
    return x;
  } else {
    const x = 2;
    return x;
  }
}
class K {
  m() {
    if (a) {
      return 1;
    } else {
      return 2;
    }
  }
}
if (a) {
  f1();
} else {
  f2();
}
function f8() {
  if (a) return 1
  else (f1());
}
function f9() {
  if (a) {
    return 1;
  } else {
    f1()
  } f2();
}

// Not reported.
function g1() {
  if (a) {
    return 1;
  }
  return 2;
}
function g2() {
  if (a) {
    f1();
  } else {
    return 2;
  }
}
function g3() {
  if (a) {
    return 1;
  } else if (b) {
    return 2;
  }
}
function g4() {
  if (a) {
    f1();
  } else if (b) {
    return 2;
  } else {
    return 3;
  }
}
function f10() {
  if (a) {
    return 1;
  } else {
    return 2;
  } /* after */
} // end
