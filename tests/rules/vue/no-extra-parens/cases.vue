<template>
  <p>{{ (a) }}</p>
  <div :a="(b + c)" />
  <div :a="((d))" />
  <div @click="(g)()" />
  <div :a="(a * b) + c" />
  <p>{{ (function () {})() }}</p>
  <p>{{ (function () {} ()) }}</p>
  <div :class="(a + b | filter)" />
</template>

<script setup lang="ts">
const v = (1)
console.log(v)
</script>

<style>
.a {
  color: v-bind('(x)');
}
</style>
