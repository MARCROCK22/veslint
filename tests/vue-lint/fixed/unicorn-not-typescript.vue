<script setup lang="ts">
function use (value?: unknown, other?: unknown) {
  return [value, other];
}

use(1);
use();
const items = [1, 2, 3];
const copy = [...items];
const bound = use.bind(null,
undefined);

function pick (kind: string | undefined) {
  switch (kind) {
  case "a":
  case undefined:
  default: {
    return copy.length + bound().length;
  }
  }
}

pick("a");
</script>
