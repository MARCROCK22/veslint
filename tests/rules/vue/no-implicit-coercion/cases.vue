<template>
  <p>{{ !!foo }}</p>
  <div :a="+foo" />
  <div :a="'' + foo" />
  <div :a="~foo.indexOf(1)" />
  <div @click="foo += ''" />
  <div :a="1 * foo" />
</template>

<script setup lang="ts">
const b = !!Math.random()
console.log(b)
</script>

<style>
.a {
  width: v-bind("'' + w");
}
</style>
