import { defineComponent, ref } from 'vue'
export default defineComponent({
  setup(_, { emit }) {
    const n = ref(1)
    emit('update', n)
    return { m: n + 1 }
  },
})
