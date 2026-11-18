import { nextTick } from 'vue'
nextTick(() => {})
export default { methods: { m() { nextTick(() => {}) } } }
