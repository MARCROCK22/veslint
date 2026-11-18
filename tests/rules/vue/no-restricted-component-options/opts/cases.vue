<script lang="ts">
export default {
  init() {},
  props: {
    foo: { type: String, required: true },
    bar: String,
  },
  ...other,
  methods: {
    a() {},
  },
}
declare const other: object
</script>
<script setup lang="ts">
defineOptions({ init: 1 })
</script>
