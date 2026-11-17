<script lang="ts">
async function later (): Promise<number> {
 return 1;
}
export default {name: "Both" };
const top = 1;
</script>

<script setup lang="ts">
// eslint-disable-next-line no-var
var count = top + 1;
later();
const unused = 2;
const x: any = 3;
x.foo;
</script>
<template><div>{{ count }}</div></template>
