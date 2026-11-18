// defineComponent in a TypeScript file: the rule's script listeners run there too.
import { defineComponent } from 'vue'
export default defineComponent({
  emits: ['used', 'unused'],
  methods: {
    f() {
      this.$emit('used')
    },
  },
})
