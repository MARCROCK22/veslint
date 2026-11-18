<template>
  <div />
</template>
<script lang="ts">
// @ts-nocheck
export default {
  props: {
    /** @public */
    p: String,
  },
  data() {
    return {
      /** @public */
      d1: 1,
      /** not public */
      d2: 2,
    }
  },
  methods: {
    /**
     * @public
     */
    // a line comment
    m1() {},
    m2: /** @public */ function () {},
    /** @publicity */
    m3() {},
    /*@public*/
    m4() {},
  },
}
</script>
