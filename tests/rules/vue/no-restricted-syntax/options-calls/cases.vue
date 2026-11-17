<template>
  <p>{{ foo() }}</p>
  <input :value="value">
  <input :[fn()]="fn()">
  <div @click="foo; bar(baz)" />
</template>

<script setup lang="ts">
console.log(foo)
</script>

<style>
.a {
  color: v-bind("foo()");
}
</style>
