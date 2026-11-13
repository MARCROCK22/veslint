// Not reported without enforceForClassMembers.
class A {
  ['m']() {}
  ['p'] = 1;
}

// Reported anyway.
const b = { ['x']: 1 };
