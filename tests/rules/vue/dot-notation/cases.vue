<template>
  <p>{{ foo['bar'] }}</p>
  <div :a="foo[`baz`]" />
  <div :a="foo['while']" />
  <div :a="foo['bad-name']" />
  <div @click="foo['run']()" />
  <div :[foo['key']]="x" />
</template>

<script setup lang="ts">
const o = { a: 1 }
console.log(o["a"])
</script>

<style>
.a {
  color: v-bind("theme['color']");
}
</style>
