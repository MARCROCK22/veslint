<template>
  <p>{{ !a ? b : c }}</p>
  <div @click="if (!a) b(); else c()" />
  <div :a="a != b ? 1 : 2" />
  <div :a="a !== b ? 1 : 2" />
  <div :a="!a ? b : !c ? d : e" />
</template>

<script setup lang="ts">
const v = !Math.random() ? 1 : 2
console.log(v)
</script>

<style>
.a {
  width: v-bind("!a ? '1px' : '2px'");
}
</style>
