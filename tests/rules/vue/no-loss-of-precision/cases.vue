<template>
  <p>{{ 9007199254740993 }}</p>
  <div :a="5123000000000000000000000000001" />
  <div :a="0.1" />
  <div :a="1230000000000000000000000.0" />
</template>

<script setup lang="ts">
const big = 9007199254740993
console.log(big)
</script>

<style>
.a {
  width: v-bind(9007199254740993);
}
</style>
