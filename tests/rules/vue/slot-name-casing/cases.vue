<template>
  <div><slot key="foo" /></div>
  <div><slot name /></div>
  <div><slot name="foo" /></div>
  <div><slot name="fooBar" /></div>
  <div><slot :name="fooBar" /></div>
  <div>
          <slot name="foo-bar" />
          <slot name="foo-Bar_baz" />
        </div>
</template>
