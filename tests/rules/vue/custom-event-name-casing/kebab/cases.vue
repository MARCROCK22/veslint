<template>
  <button @click="$emit('fooBar')" />
  <button @click="$emit('foo-bar')" />
  <button @click="$emit('ignored-Thing')" />
</template>
<script lang="ts">
export default {
  setup(props, context) {
    context.emit('ctxEvent')
    context.emit('ctx-event')
    context?.emit('ctxOpt')
  }
}
</script>
