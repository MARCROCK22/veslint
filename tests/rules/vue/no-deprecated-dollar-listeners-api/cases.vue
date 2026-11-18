<template>
  <div v-bind="$listeners" @click="$listeners.click()">
    <child v-for="$listeners in list" :x="$listeners" />
    {{ $listeners }}
  </div>
</template>
<script lang="ts">
export default {
  mounted() {
    const vm = this
    console.log(this.$listeners, vm.$listeners, this?.$listeners, this['$listeners'], other.$listeners)
  },
  data() {
    return { a: this.$listeners }
  }
}
const notVue = { m() { return this.$listeners } }
</script>
