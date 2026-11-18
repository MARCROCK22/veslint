<template>
  <div :a="{ my_pref: 1, your_pref: 2 }" />
  <div @click="const { my_value } = $event" />
</template>

<script setup lang="ts">
console.log(my_global_ref)
</script>
