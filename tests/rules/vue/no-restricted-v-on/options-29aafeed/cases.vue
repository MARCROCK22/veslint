<template>
  <div><div @v-on="foo" @foo.prevent="bar" /><div @foo="foo" v-on="listener" /></div>
</template>
