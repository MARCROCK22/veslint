<script lang="ts">
import FooBar from './FooBar.vue'
import Baz from './Baz.vue'
export default {
  components: {
    FooBar,
    'foo-bar': FooBar,
    fooBar: FooBar,
    Qux: Baz,
    ['Computed']: Baz,
    ...{ Spread: Baz },
    Call: f(),
    1: Baz,
  },
}
declare function f(): any
</script>
