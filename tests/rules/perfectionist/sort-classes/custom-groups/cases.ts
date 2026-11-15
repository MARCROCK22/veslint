declare function Input(): any;
class CustomGroups {
  zeta = 1;
  get value() {
    return 1;
  }
  method() {}
  onClick = () => {};
  static readonly MAX = 1;
  map = new Map();
  @Input() name = '';
  other = 2;
}
class CustomGroupsSorted {
  @Input() name = '';

  map = new Map();

  onClick = () => {};

  static readonly MAX = 1;

  method() {}
  other = 2;

  zeta = 1;
}
