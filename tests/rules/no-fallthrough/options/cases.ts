declare function work(n: number): void;
// Reported: the default comment is no longer enough, and an unused comment.
function custom(n: number): void {
  switch (n) {
    case 1:
      work(1);
    // falls through
    case 2:
      work(2);
      break;
    // break omitted
    case 3:
      work(3);
  }
}
// Not reported: the custom comment, and an empty case with a blank line.
function allowed(n: number): void {
  switch (n) {
    case 1:
      work(1);
    // break intentionally omitted
    case 2:

    case 3:
      work(3);
  }
}
export { custom, allowed };
