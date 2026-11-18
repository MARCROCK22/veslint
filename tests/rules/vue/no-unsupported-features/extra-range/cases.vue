<script setup lang="ts">
  const model = defineModel<string>()
const slots = defineSlots<{ default(): unknown }>()
	defineOptions({ name: 'Foo', inheritAttrs: false })
</script>

<template>
  <MyComponent v-slot:[name]="{ item }" :data-x .prop-y v-model:value.foo.trim="x" v-bind:a.attr="b">
    <template #[dyn].mod="{ a }">{{ a }}</template>
    <template v-slot:named>x</template>
    <template v-slot>y</template>
    <div slot-scope="s" v-memo="[a]" v-is="'foo'" is="vue:bar"></div>
    <input v-model:[arg]="value" .prop="z">
  </MyComponent>
</template>

<style>
.a { color: v-bind(color); }
.b { color: v-bind('theme.color'); }
</style>
