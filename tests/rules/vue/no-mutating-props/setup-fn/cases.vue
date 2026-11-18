<script lang="ts">
import { defineComponent } from 'vue'
export default defineComponent({
  props: { foo: String, bar: Object, list: Array },
  setup(props, { emit }) {
    props.foo = 'a'
    const { bar, list: [first], ...rest } = props
    bar.x = 1
    first.y = 2
    rest.list = []
    emit('x')
  },
})
</script>
