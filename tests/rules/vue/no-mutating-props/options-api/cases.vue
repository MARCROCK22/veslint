<template>
  <div @click="this.foo = 1">{{ foo }}</div>
  <input v-model="bar.baz" />
</template>
<script lang="ts">
import { defineComponent } from 'vue'
export default defineComponent({
  props: ['foo', 'bar'],
  methods: {
    m() {
      this.foo = 2
      this.bar.baz++
      this.bar.list.splice(0, 1)
      const self = this
      self.foo = 3
    },
  },
})
</script>
