<script setup lang="tsx">
const a = (1 as unknown) as string;
</script>

<template>
  <p>{{ <string>a }}</p>
</template>
