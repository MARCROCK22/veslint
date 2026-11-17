<template>
  <div><div :foo /></div>
  <div>
      <div :foo.prop />
      <div .foo />
      </div>
  <div><div :foo-bar/></div>
  <div><div :foo-bar="foo_bar" /></div>
  <div><div :foo="foo" /></div>
  <div><div :foo_bar="foo_bar" /></div>
  <div><div :foo.prop="foo" /></div>
  <div><div .foo="foo" /></div>
  <div><div :foo-bar="fooBar" /></div>
</template>
