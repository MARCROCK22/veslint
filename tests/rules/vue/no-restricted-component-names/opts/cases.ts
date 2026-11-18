import { defineComponent } from 'vue'
defineComponent({ name: 'FooBar' })
defineComponent({ name: 1 })
defineComponent({ name: null })
defineComponent({ name: 'Other' })
defineComponent({ ['name']: 'foo-bar' })
