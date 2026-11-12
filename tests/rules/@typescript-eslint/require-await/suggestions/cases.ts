declare function log(...args: unknown[]): void;
declare const key: unique symbol;
declare const cond: boolean;
declare function async(...args: unknown[]): any;
declare function wrap(...args: unknown[]): any;

async function plain() {
  log();
}
async /* c */ function commented() {
  log();
}
async function withPromise(): Promise<void> {
  log();
}
async function withNested(): Promise<Array<Map<string, number>>> {
  return [];
}
async function qualified(): globalThis.Promise<void> {
  log();
}
async function parenthesized(): (Promise<number>) {
  return 1;
}
async function unionReturn(): Promise<void> | Promise<number> {
  log();
}
async function commentedType(): Promise /* a */ < /* b */ number /* c */ > /* d */ {
  return 1;
}
async function arrowInType(): Promise<() => void> {
  return () => {};
}
async function* gen(): AsyncGenerator<number> {
  yield 1;
}
async function* genBare(): AsyncGenerator {
  yield 1;
}
async function* genIterable(): AsyncIterableIterator<number> {
  yield 1;
}
async function* genPromise(): Promise<number> {
  yield 1;
}
async function notGen(): AsyncGenerator<number> {
  return null!;
}
async function* genQualified(): globalThis.AsyncGenerator<number> {
  yield 1;
}
const arrow = async () => {
  log();
};
const arrowTyped = async (): Promise<number> => 1;
const arrowParam = async (x: number) => x;
const arrowBare = async x => x;
const arrowGeneric = async <T,>(x: T): Promise<T> => x;
const fnExpr = async function () {
  log();
};
const fnNamed = async function named(): Promise<void> {
  log();
};
const genExpr = async function* (): AsyncGenerator<string, void> {
  yield '';
};
const obj = {
  async method() {
    log();
  },
  async [key]() {
    log();
  },
  async *gen(): AsyncGenerator<number> {
    yield 1;
  },
  prop: async () => {
    log();
  },
  fn: async function (): Promise<void> {
    log();
  },
  async 'quoted'(): Promise<string> {
    return '';
  },
  async /* c */ commented(): Promise<number> {
    return 1;
  },
};
class Members {
  async method() {
    log();
  }
  static async staticMethod(): Promise<void> {
    log();
  }
  public static async modifiers(): Promise<number> {
    return 1;
  }
  async [key]() {
    log();
  }
  x = 1
  async ['after-field']() {
    log();
  }
  y = 1;
  async ['after-semicolon']() {
    log();
  }
  z = () => {}
  async ['after-arrow']() {
    log();
  }
  w = function () {}
  async ['after-function']() {
    log();
  }
  async *gen() {
    yield 1;
  }
  @async async decorated() {
    log();
  }
  @wrap(async) async decoratedCall() {
    log();
  }
  @wrap
  // comment
  async decoratedComment(): Promise<void> {
    log();
  }
  v = 1
  @wrap async ['decorated-after-field']() {
    log();
  }
  field = async () => {
    log();
  };
  async #priv() {
    log();
  }
  static {
    void this.prototype.#priv;
  }
}
log()
async () => {
  log();
}
const a = 1
async (x: number): Promise<number> => x
if (cond) async () => { log(); }
{
  async () => { log(); }
}
log(); async () => { log(); }
label: async () => { log(); }
const arrowBefore = () => {}
async () => { log(); }
void (function () {})
async () => { log(); }
do log(); while (cond)
async () => { log(); }
const o = {}
async () => { log(); }
class K {}
async () => { log(); }
const k = class {}
async () => { log(); }
const f2 = function () {}
async () => { log(); }
log(`a`)
async () => { log(); }, 1
log()
async x => x
const résumé = '🎉é'; const late = async (): Promise<string> => résumé;
void [plain, commented, withPromise, withNested, qualified, parenthesized, unionReturn];
void [commentedType, arrowInType, gen, genBare, genIterable, genPromise, notGen, genQualified];
void [arrow, arrowTyped, arrowParam, arrowBare, arrowGeneric, fnExpr, fnNamed, genExpr, obj];
void [Members, a, o, K, k, f2, late, arrowBefore];
// @ts-expect-error: a bare Promise is not a valid type, but it is a type reference without arguments
async function bare(): Promise {
  log();
}
export async function exported(): Promise<void> {
  const inner = async (): Promise<number> => 1;
  void inner;
}
export default async function (): Promise<void> {
  log();
}
namespace Inner {
  export const nested = {
    async deep(): Promise<Array<Promise<number>>> {
      return [];
    },
  };
}
void [bare, Inner];
