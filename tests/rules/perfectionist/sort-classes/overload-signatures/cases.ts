class Overloads {
  b(): void;

  b(value: number): void;
  b(value?: number) {}
  a(): void;
  a(value?: number) {}
}
class OverloadsSorted {
  a(): void;
  a(value?: number) {}

  b(): void;
  b(value?: number) {}
}
