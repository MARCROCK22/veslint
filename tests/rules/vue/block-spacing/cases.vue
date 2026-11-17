<template>
  <div @click="() => {doIt()}" />
  <div @click="if (a) {b()}" />
  <div :a="function () {return 1}" />
  <div :[(function(){return(1)})()]="x" />
  <div @click="() => { ok() }" />
</template>

<script setup lang="ts">
function f() {return 1}
console.log(f)
</script>
