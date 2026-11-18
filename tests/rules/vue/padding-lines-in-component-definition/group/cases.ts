import { defineComponent } from 'vue'
defineComponent({
  name: 'A',

  inheritAttrs: false,
  props: {
    a: String,
  },
  emits: ['x'], methods: {},
})
