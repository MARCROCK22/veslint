<template>
  <div :a="{ a: a }" />
  <p>{{ { f: function () { return 1 } } }}</p>
  <div :a="{ x: () => 1 }" />
  <div :a="{ 'b': b }" />
  <div :[{c:c}.c]="y" />
</template>

<script setup lang="ts">
const a = 1
console.log({ a: a })
</script>
