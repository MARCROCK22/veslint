// typescript-eslint 8.72: the declarations of an enum merged across declarations of a namespace,
// of `declare global` and of nested qualified namespaces; one without members does not count.
export {};
namespace Outer {
  export enum Merged {
    A = 1,
  }
}
namespace Outer {
  export enum Merged {
    B = 'B',
  }
}
namespace EmptyFirst {
  export enum E {}
}
namespace EmptyFirst {
  export enum E {
    B = 'B',
  }
}
namespace NotExported {
  enum Local {
    A = 1,
  }
}
namespace NotExported {
  export enum Local {
    B = 'B',
  }
}
declare global {
  export enum GlobalEnum {
    A = 1,
  }
}
declare global {
  export enum GlobalEnum {
    B = 'B',
  }
}
namespace A.B {
  export enum Q {
    A = 'a',
  }
}
namespace A.B {
  export enum Q {
    B = 2,
  }
}
export namespace Nested {
  export namespace Inner {
    export enum N {
      A = 1,
    }
  }
}
export namespace Nested {
  export namespace Inner {
    export enum N {
      B = 'b',
    }
  }
}
declare module 'virtual' {
  export enum V {
    A = 1,
  }
}
declare module 'virtual' {
  export enum V {
    B = 'b',
  }
}
