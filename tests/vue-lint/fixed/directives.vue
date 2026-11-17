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
const c = 3;
// eslint-disable-next-line prefer-const
let value = a + b + c;
const other = 4;

const unusedDirective = value + other;
export default {"data": () => ({value,
unusedDirective})};
</script>
