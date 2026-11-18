<script lang="ts">
export default function (props: { a: number }) {
  const inner = () => {
    return 1
  }
  inner()
}
</script>
