<script setup lang="tsx">
const a = <b>{1}</b>
</script>

<template>
  <p>{{ <string>a }}</p>
  <p :title="<i />"></p>
</template>
