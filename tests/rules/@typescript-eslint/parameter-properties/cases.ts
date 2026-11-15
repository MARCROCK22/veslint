declare function dec(...args: unknown[]): any;
// Reported: every parameter property.
class A {
  constructor(
    readonly a: number,
    private b: string,
    protected c = 1,
    public d?: number,
    private readonly e: number,
    protected readonly f: number,
    public readonly g: number,
    override h: number,
    @dec readonly i: number,
    readonly ñ: number,
  ) {}
}
// Not reported.
class B {
  constructor(a: number, b = 1, ...c: number[]) {}
}
