import { defineComponent, h } from 'vue'
export const empty = defineComponent({})
export const inline = defineComponent({ props: ['x'] })
export const exposed = defineComponent({ expose: [], props: ['x'] })
export const called = defineComponent({
  setup(_, { expose }) {
    expose({})
  },
})
export const ctx = defineComponent({
  setup(_, context) {
    context.expose()
  },
})
export const render = defineComponent({
  setup() {
    return () => h('div')
  },
})
export const arrow = defineComponent({ setup: () => () => h('div') })
export const multiline = defineComponent({
})
export const computedKey = defineComponent({ ['expose']: [] })
