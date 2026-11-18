<script lang="ts">
export default {
  props: {
    a: { type: String, required: true },
    b: {
      type: Number,
      default: 1,
    },

    c: Boolean,
  },
  emits: {
    x: null,
    y: null,
  },
}
</script>
<script setup lang="ts">
defineProps({
  a: String,
  b: {
    type: Number,
  },
})
defineEmits({ x: null, y: null })
</script>
