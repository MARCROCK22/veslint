// no-unused-private-class-members with CRLF line breaks: the raw text of a template key keeps them.
class C {
  private [`a
b`] = 1;
  private [`c
d`] = 2;
  private [`e
f`] = 3;
  m() {
    return [this[`c
d`], this[`e
f`]];
  }
}
export { C };
