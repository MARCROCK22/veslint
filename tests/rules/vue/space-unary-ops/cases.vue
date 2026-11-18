<template>
  <p>{{ - a }}</p>
  <div :a="! b" />
  <div :a="typeof(a)" />
  <div @click="i ++" />
  <div :a="new Foo" />
  <div :a="void(0)" />
</template>

<script setup lang="ts">
let i = 0
i ++
console.log(- i)
</script>

<style>
.a {
  width: v-bind("- w");
}
</style>
