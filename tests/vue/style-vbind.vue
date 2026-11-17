<template><div /></template>
<style>
.a { color: v-bind(color); width: v-bind( "w.x" ); height: v-bind  (k); }
.b { margin: v-bind(/* c */ 'm' /* d */); padding: v-bind(p + 'px') }
.c { content: v-bind(); top: v-bind(bad +) }
</style>
<style lang="scss">
// line comment v-bind(nope)
.d { color: v-bind(theme.color) }
</style>
<style scoped>.e { color: red }</style>
