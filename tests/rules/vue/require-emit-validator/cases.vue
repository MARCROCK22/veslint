<script lang="ts">
export default {
  emits: {
    a: null,
    b: () => true,
    c: validator,
    d: 'x',
    ...other,
    [key]: null,
  },
}
declare const validator: any
declare const other: any
declare const key: string
</script>
