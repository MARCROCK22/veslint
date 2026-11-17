<template>
  <div><component is="foo" /></div>
  <div><div /></div>
  <div><Foo is="foo" /></div>
  <div><component :is="'foo'" /></div>
  <div><div is="vue:foo" /></div>
  <div><div is="foo" /></div>
  <div><div :is="foo" /></div>
</template>
