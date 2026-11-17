<template>
  <div>
    <slot name="fooBar" />
    <slot name="foo-bar" />
    <slot name="foo_bar" />
    <slot name="FooBar" />
    <slot name="foo" />
    <slot name="" />
    <slot name />
    <slot :name="x" />
    <Slot name="Abc" />
    <slot name="élan" />
  </div>
</template>
