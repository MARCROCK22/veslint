declare const a: boolean;

// Reported.
function f1() {
  try {
    return 1;
  } finally {
    return 2;
  }
}
function f2() {
  try {
  } finally {
    throw new Error();
  }
}
function f3() {
  for (;;) {
    try {
    } finally {
      break;
    }
  }
}
function f4() {
  for (;;) {
    try {
    } finally {
      continue;
    }
  }
}
function f5() {
  outer: for (;;) {
    try {
    } finally {
      break outer;
    }
  }
}
function f6() {
  try {
  } finally {
    if (a) {
      return;
    }
  }
}
function f7() {
  label: try {
  } finally {
    break label;
  }
}

// Not reported.
function g1() {
  try {
  } finally {
    const h = () => {
      return 1;
    };
    function k() {
      throw new Error();
    }
    class L {
      m() {
        return 1;
      }
    }
  }
}
function g2() {
  try {
  } finally {
    for (;;) {
      break;
    }
    while (a) {
      continue;
    }
    switch (1) {
      case 1:
        break;
    }
    inner: {
      break inner;
    }
  }
}
