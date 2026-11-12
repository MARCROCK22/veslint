declare let a: any;

// Reported with checkLoops "all".
while (true) {}
while (1) {}
do {} while (true);
for (; true; ) {}
function* gen() {
  for (yield; true; ) {}
  while (true) {
    function* inner() {
      yield;
    }
  }
  while (true) {
    const g = function* () {
      yield;
    };
  }
  while (true) {
    while (true) {
      yield;
    }
  }
}

// Not reported.
while (a) {}
function* gen2() {
  while (true) {
    yield;
  }
  for (; true; yield) {}
  for (; (yield, true); ) {}
}
