<template>
  <div><div :v-on :foo.sync /><div :foo="foo" v-bind="listener" /></div>
</template>
