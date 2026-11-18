<script lang="ts">
export default {
  computed: {
    a() {},
    b: {
      get() {
        if (Math.random()) {
          return 1
        }
      },
    },
    c() {
      return
    },
    d: function () {
      return 1
    },
    [`e`]() {},
    [x]() {},
  },
}
declare const x: string
</script>
