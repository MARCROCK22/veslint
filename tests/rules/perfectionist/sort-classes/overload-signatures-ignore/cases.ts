class OverloadsIgnore {
  a(): void;

  a(value: number): void;
  a(value?: number) {}
  b() {}
}
class StaticOverloads {
  static b(): void;
  static b(value?: number) {}
  static a() {}
}
