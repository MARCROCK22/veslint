<script lang="ts">
export default {
  emits: ['first'],
  setup(props, { emit }) {
    helper(emit)
  },
  methods: {}
}
const second = { emits: ['second'] }
</script>
<script lang="ts">
</script>
