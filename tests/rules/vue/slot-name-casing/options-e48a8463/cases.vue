<template>
  <div>
          <slot name="foo" />
          <slot :name="fooBar" />
        </div>
  <div>
          <slot name="foo-bar" />
          <slot name="fooBar" />
          <slot name="foo-Bar_baz" />
        </div>
</template>
