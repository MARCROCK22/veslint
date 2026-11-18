<script lang="ts">
export default {
  props: ['a', 'b'],
  computed: {
    a(): number {
      return 1
    },
  },
  data() {
    return { b: 1, c: 2 }
  },
  methods: { c() {} },
  setup() {
    return { d: 1 }
  },
  foo: { d: 1 },
}
</script>
