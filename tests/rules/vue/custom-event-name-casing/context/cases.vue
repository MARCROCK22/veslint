<script lang="ts">
import { defineComponent } from 'vue'
export default defineComponent({
  methods: {
    early() { emit('before-setup') }
  },
  setup(props, { emit }) {
    emit('in-setup')
    const inner = defineComponent({ methods: { m() { emit('inner-object') } } })
  }
})
</script>
