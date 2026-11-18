<template>
  <div ref="a" />
</template>
<script lang="ts">
export default {
  mounted() { foo(this.$refs) }
}
</script>
