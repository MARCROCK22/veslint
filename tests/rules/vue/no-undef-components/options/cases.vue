<template>
  <div>
    <foo-bar /><FooBar /><Registered /><registered /><kebab-reg /><KebabReg /><SelfName />
    <component :is="'Lit'" /><div v-is="'Lit2'" /><component :is="5" /><component :is="dyn" />
  </div>
</template>
<script lang="ts">
export default {
  name: 'SelfName',
  components: { Registered: {}, 'kebab-reg': {}, FooBar: {} },
}
</script>
