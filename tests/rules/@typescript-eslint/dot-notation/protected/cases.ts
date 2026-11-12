// dot-notation with allowProtectedClassPropertyAccess and allowIndexSignaturePropertyAccess.
abstract class Shape {
  protected abstract area: number;
  protected static count = 0;
  protected readonly sides = 4;
  private secret = 1;
  [key: string]: number;
}

export class Square extends Shape {
  protected area = 1;
  measure(): number {
    // Not reported: protected members (inherited too) and index signature keys.
    // Reported: the private member.
    return this['area'] + this['sides'] + Square['count'] + this['other'] + this['secret'];
  }
}

interface Bag {
  [key: string]: number;
  known: number;
}
declare const bag: Bag;
// Reported: a declared property; not reported: an index signature key.
void bag['known'];
void bag['unknown'];
