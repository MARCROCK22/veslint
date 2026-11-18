<template>
  <div ref="a" />
  <div ref="b" />
  <div ref="c" />
</template>
<script lang="ts">
export default {
  methods: {
    m() {
      ({ a: x } = this.$refs)
      const r: typeof this.$refs = 1 as any
      for (const k in this.$refs) {}
    }
  }
}
</script>
