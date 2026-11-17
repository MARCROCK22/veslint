<template>
  <div><div :foo="foo" /></div>
  <div>
      <div :foo.prop="foo" />
      <div .foo="foo" />
      </div>
  <div><div :foo-bar="fooBar" /></div>
  <div><div :foo /></div>
  <div><div :foo.prop /></div>
  <div><div .foo /></div>
  <div><div :foo-bar /></div>
  <div><div :foo_bar /></div>
</template>
