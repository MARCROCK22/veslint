<script setup lang="ts">
function use(value?: unknown, other?: unknown) {
  return [value, other];
}

use(1, undefined);
use(undefined);
const items = [1, 2, 3];
const copy = items.slice();
const bound = use.bind(null, undefined);

function pick(kind: string | undefined) {
  switch (kind) {
    case undefined:
    case 'a':
    default:
      return copy.length + bound().length;
  }
}

pick('a');
</script>
