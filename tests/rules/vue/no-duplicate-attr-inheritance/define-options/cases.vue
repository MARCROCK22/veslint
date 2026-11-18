<template>
  <div v-bind="$attrs" />
</template>
<script setup lang="ts">
defineOptions({ inheritAttrs: false })
</script>
<script lang="ts">
export default { inheritAttrs: 'yes' }
</script>
