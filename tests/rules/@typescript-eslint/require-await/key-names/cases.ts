// The name of a method in the message is eslint-utils' getPropertyName without a scope: a static
// key gives its value, but no identifier is resolved.
const k = 'viaConst';
class Names {
  async ['a' + 'b']() {
    return 1;
  }
  async [`t${1}`]() {
    return 1;
  }
  async ['\x61']() {
    return 1;
  }
  async '\x62'() {
    return 1;
  }
  async 0x10() {
    return 1;
  }
  async [1 + 2]() {
    return 1;
  }
  async [k]() {
    return 1;
  }
  async [String(1)]() {
    return 1;
  }
  async 1e3() {
    return 1;
  }
  async ['c'.concat('d')]() {
    return 1;
  }
  async [`plain`]() {
    return 1;
  }
}
const obj = {
  async ['e' + 'f']() {
    return 1;
  },
  async [-1]() {
    return 1;
  },
  async 1.50() {
    return 1;
  },
  async [void 0 as never]() {
    return 1;
  },
};
export { Names, obj };
