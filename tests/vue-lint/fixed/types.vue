<script lang="ts">
import {count} from "./util";

export function size (items: string[]) {
  return count(items);
}
</script>

<script setup lang="ts">
import {onMounted, ref} from "vue";

import {load} from "./util";

const items = ref<string[]>([]);
const value = "x";
if (value) {
  items.value.push(value);
}
onMounted(async () => {
  items.value = [await load(size(items.value))];
});
const result = await Promise.resolve(1);
const flag = items.value.length > 0
  ? true
  : false;
[1, 2].forEach(async (n) => {
  await load(n + result);
});
</script>

<template>
  <ul>
    <li
      v-for="item in items"
      :key="item"
    >
      {{ item }} {{ flag }}
    </li>
  </ul>
</template>
