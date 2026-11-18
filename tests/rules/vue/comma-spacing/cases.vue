<template>
  <p>{{ fn(a ,b) }}</p>
  <div :a="[a,b]" />
  <div v-for="(item,index) in list" :key="index" />
  <Comp v-slot="{a ,b}">x</Comp>
  <div :[fn(a,b)]="x" />
  <div :a="[a, , b]" />
</template>

<script setup lang="ts">
const list = [1 ,2]
console.log(list)
</script>

<style>
.a {
  color: v-bind("fn(a,b)");
}
</style>
