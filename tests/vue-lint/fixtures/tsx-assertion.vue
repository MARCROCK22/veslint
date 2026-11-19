<script setup lang="tsx">
const a = <string>(1 as unknown)
</script>

<template>
  <p>{{ <string>a }}</p>
</template>
