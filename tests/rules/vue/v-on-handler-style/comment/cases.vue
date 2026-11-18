<template>
  <button @click="foo(/* c */)" />
  <button @click="() => foo() // c
  " />
</template>
<script setup lang="ts">
function foo() {}
</script>
