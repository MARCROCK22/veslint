<template>
  <div :a="{ my_pref: 1 }" />
  <div @click="obj.some_prop = 1" />
  <div @click="const { my_pref } = $event" />
</template>

<script setup lang="ts">
console.log(other_global_x)
</script>
