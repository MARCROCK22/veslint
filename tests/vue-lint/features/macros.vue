<script setup lang="ts">
const props = defineProps<{ a: string }>()
const custom = defineCustom()
</script>

<template>
  <p>{{ props.a }} {{ custom }}</p>
</template>
