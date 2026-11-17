<template>
  <div><p foo /></div>
  <div><p foo="bar" /></div>
  <div><p foo-bar /></div>
  <div><p _foo-bar /></div>
  <div><p :foo-bar /></div>
  <div><p foo.bar /></div>
  <div><p quux-.9 /></div>
  <div><MyComponent 0abc="foo" /></div>
  <div><MyComponent :0abc="foo" /></div>
  <div><a :href="url"> ... </a></div>
  <div><div v-bind:class="{ active: isActive }"></div></div>
  <div><p v-if="seen">Now you see me</p></div>
  <div><div v-bind="..."></div></div>
  <div><div v-0abc="..."></div></div>
  <div><p 0abc /></div>
  <div><p -def></div>
  <div><p !ghi /></div>
  <div><p v-bind:0abc=""></div>
  <div><p :0abc="..." /></div>
</template>
