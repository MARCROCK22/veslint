<script lang="ts">
export default {
  props: {
    a: 'String',
    b: ['Number', Boolean, `Array`],
    c: { type: 'Object' },
    d: { type: null },
    e: 1 + 1,
    f: { type: '' },
    g: String,
  },
}
</script>
