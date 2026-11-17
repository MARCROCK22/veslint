<script setup lang="tsx">
const el = <div class="x">{a}</div>
</script>
<template><div :a="<T,>(x: T) => x" /></template>
