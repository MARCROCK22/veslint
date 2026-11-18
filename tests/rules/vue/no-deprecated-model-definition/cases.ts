import { defineComponent } from 'vue'
defineComponent({
  model: { prop: 'modelValue', event: 'update:modelValue' },
})
defineComponent({
  model: 'nope',
})
