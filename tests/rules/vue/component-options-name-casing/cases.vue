<script lang="ts">
export default {
  components: {
    fooBar,
    'foo-bar': fooBar,
    FooBar: fooBar,
    foo_bar: fooBar,
    ['computedKey']: fooBar,
    ...spread,
  },
}
declare const fooBar: any
declare const spread: any
</script>
