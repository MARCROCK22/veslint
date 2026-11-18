<template>
  <div><Named /><Opt /><Plain /></div>
</template>
<script setup lang="ts">
defineOptions({ name: 'Opt' })
</script>
<script lang="ts">
export default { name: 'Named', components: { Plain: {} } }
</script>
