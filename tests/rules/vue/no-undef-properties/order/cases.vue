<template>
  <div>{{ dup }} {{ dup2.a }}</div>
</template>
<script lang="ts">
export default {
  methods: {
    m() {
      return (this as any).dup2
    },
  },
}
</script>
<style>
.a { color: v-bind(dup); }
</style>
