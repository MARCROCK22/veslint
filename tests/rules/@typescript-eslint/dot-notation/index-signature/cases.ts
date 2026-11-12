// dot-notation with allowIndexSignaturePropertyAccess: true.
interface Mixed {
  known: number;
  __proto: number;
  [key: string]: number;
}
declare const mixed: Mixed;
declare const optional: Mixed | undefined;
declare const numeric: { [index: number]: string; length: number };
declare const templated: { [key: `data${string}`]: string; plain: string };
declare const record: Record<string, number>;

// Not reported: the key matches only the string index signature.
mixed['other'];
mixed[`other`];
mixed[('other')];
optional?.['other'];
optional!['other'];
record['anything'];
templated['dataX'];
// @ts-expect-error -- `true` is not a valid index type.
mixed[true];

// Reported: the key is a declared property.
mixed['known'];
mixed[`known`];
mixed[('known')];
optional?.['known'];
templated['plain'];
mixed['__proto'];

// Not reported: the fallback compares the escaped name (`___proto`) with the key.
mixed[('__proto')];

// Reported: no string index signature.
numeric['length'];
// @ts-expect-error -- no index signature for `other`.
numeric['other'];

class Secret {
  private hidden = 1;
  protected guarded = 2;
  read(): number {
    // Reported: private and protected members (those options are not set).
    return this['hidden'] + this['guarded'];
  }
}
void Secret;
