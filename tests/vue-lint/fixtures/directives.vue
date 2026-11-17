<!-- eslint-disable -->
<template>
  <!-- eslint-disable-next-line vue/no-unused-vars -->
  <div>{{ value }}</div>
</template>

<script lang="ts">
/* eslint-disable no-var */
var a = 1;
var b = 2;
/* eslint-enable no-var */
var c = 3;
// eslint-disable-next-line prefer-const
let value = a + b + c;
let other = 4; // eslint-disable-line @typescript-eslint/no-unused-vars
// eslint-disable-next-line no-console
const unusedDirective = value + other;
export default { data: () => ({ value, unusedDirective }) };
</script>
