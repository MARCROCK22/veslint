<script lang="ts">
export default {
  components: {
    FooBar,
    fooBar: FooBar,
    'foo-bar': FooBar,
  },
}
declare const FooBar: any
</script>
