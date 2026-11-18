<template>
  <div :a="(x)=>x" />
  <div :a="(x) =>x" />
  <div :a="(x)=> x" />
  <div :a="(x) => x" />
  <div @click="() =>doIt()" />
  <div @click="(e)=>{ handle(e) }" />
  <p>{{ list.map(i=>i * 2) }}</p>
  <Comp v-slot="{ f = (a)=>a }">{{ f }}</Comp>
</template>

<script setup lang="ts">
const f = (a: number)=>a
console.log(f)
</script>
