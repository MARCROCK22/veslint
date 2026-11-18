<script lang="ts">
export default {
  name: 'X',
  data() { return {} },
  methods: { m() { this.$emit('a') } },
}
const other = { methods: { n() { this.$emit('b') } }, ...spread }
</script>
<script lang="ts">
</script>
