<template>
  <div v-for="item in items" :key="item.id">
    <div v-for="item in item.children" :title="item.name + outer">
      <comp v-slot="{ item: slotItem, x = item }">{{ slotItem }} {{ x }} {{ item }}</comp>
    </div>
    <button @click="item.n++; other = item; let z = 1; z = 2">{{ Math.max(item.a, Infinity) }}</button>
    <span :a="(item as Item).value" :b="<Item>item" :c="item!" :d="arguments"></span>
    {{ x => x + item }} {{ function (item) { return item + arguments.length } }}
    {{ [1, 2].map(n => n * factor) }}
    {{ obj?.[key] }} {{ { [computedKey]: v, shorthand } }}
  </div>
  <div :class="item"></div>
</template>
<script setup lang="ts" generic="Item extends { id: number }">
defineProps<{ items: Item[] }>()
</script>
