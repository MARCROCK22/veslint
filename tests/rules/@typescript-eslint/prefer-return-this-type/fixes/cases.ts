// prefer-return-this-type: the fix replaces the type reference with `this`.
// Non-ASCII text before the ranges: ñ 😀 日本語.
export class Wide<TKey, TValue> {
  // The whole reference, with its type arguments on several lines and a comment inside.
  self(): Wide<
    TKey, // the key
    TValue
  > {
    return this;
  }

  // Only the reference inside the union.
  maybe(): /* before */ Wide<TKey, TValue> /* after */ | null {
    return this;
  }

  // Inside parentheses: the parentheses stay.
  wrapped(): (Wide<TKey, TValue>) | undefined {
    return this;
  }

  arrow = (): Wide<TKey, TValue> => this;
}
