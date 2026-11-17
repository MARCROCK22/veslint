<template>
  <div><div :foo="foo"></div></div>
  <div><div .foo="foo"></div></div>
  <div><div .foo.sync="foo"></div></div>
  <div><div .foo.prop="foo"></div></div>
  <div><div .foo.sync.prop="foo"></div></div>
  <div><div :foo /></div>
</template>
