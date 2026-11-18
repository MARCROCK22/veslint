import { defineComponent } from 'vue'
export default defineComponent({
  methods: {
    m() {
      return (this as any).nope
    },
  },
})
