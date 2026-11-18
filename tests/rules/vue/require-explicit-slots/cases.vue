<template>
  <div>
    <slot />
    <slot name="foo" />
    <slot name="bar" />
    <slot :name="'baz'" />
    <slot :name="`qux`" />
    <slot :name="dynamic" />
    <slot name="" />
    <slot name />
    <slot :name="''" />
    <slot name="fromAlias" />
  </div>
</template>
<script setup lang="ts">
type Alias = { fromAlias(): any }
const dynamic = 'x'
defineSlots<{
  default(props: { msg: string }): any
  foo: (props: {}) => any
  'baz'(): any
  [key: string]: any
  foo(): any
} & Alias>()
</script>
