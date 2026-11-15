interface Short { a: 1 }
interface Longer { b: 1 }
interface Longest { c: 1 }
interface I1 extends Short, Longest, Longer {}
interface I2 extends Longest, Longer, Short {}
