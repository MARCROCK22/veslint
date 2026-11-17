<template>
  <div :a="{ my_pref: 1, okName: 2, 'quoted_key': 3, [computed_key]: 4 }" />
  <div @click="obj.some_prop = 1" />
  <div @click="foo.bar_baz" />
  <div @click="($event) => { const { my_pref } = $event; let other_var = 1; use(other_var) }" />
  <div @click="const { first_name: alias_name } = $event" />
  <div @click="function my_handler(a_b) { return a_b }" />
  <div v-for="(item_value, idx) in items" :key="idx">{{ item_value }}</div>
  <Comp v-slot="{ slot_prop }">{{ slot_prop }} {{ some_global }}</Comp>
  <div :a="{ __proto__: null, CONST_VALUE: 1, _private: 2 }" />
</template>

<script setup lang="ts">
const local_value = 1
const total = my_unknown_global + local_value
console.log(total)
</script>
