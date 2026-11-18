<script lang="ts">
export default {
  props: ['$el', 'ok'],
  computed: {
    $on() {},
    get $data() { return 1 },
    set $data(v) {},
  },
  data() {
    return { _private: 1, $emit: 2 }
  },
  asyncData: () => ({ _x: 1 }),
  methods: { $nextTick() {} },
  setup: () => ({ $watch: 1 }),
}
</script>
