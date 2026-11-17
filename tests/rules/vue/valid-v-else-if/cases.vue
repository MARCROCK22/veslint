<template>
  <div><div><div v-if="foo"></div><div v-else-if="foo"></div></div></div>
  <div><div><div v-if="foo"></div><div v-else-if="foo"></div><div v-else-if="foo"></div></div></div>
  <div>
    <c1 v-if="1" />
    <c2 v-else-if="1" />
    <c3 v-else />
</div>
  <div><div v-if="foo"></div><div v-else-if="."></div></div>
  <div><div v-if="foo"></div><div v-else-if="/**/"></div></div>
  <div><template v-else-if="foo"><div></div></template></div>
  <div><div v-else-if="foo"></div></div>
  <div><div><div v-else-if="foo"></div></div></div>
  <div><div><div></div><div v-else-if="foo"></div></div></div>
  <div><div><div if="foo"></div><div v-else-if="foo"></div></div></div>
  <div><div><div v-if="foo"></div><div></div><div v-else-if="foo"></div></div></div>
  <div><div><div v-if="foo"></div><div v-else-if="foo" v-if="bar"></div></div></div>
  <div><div><div v-if="foo"></div><div v-else-if="foo" v-else></div></div></div>
  <div><div><div v-if="foo"></div><div v-else-if:aaa="foo"></div></div></div>
  <div><div><div v-if="foo"></div><div v-else-if.aaa="foo"></div></div></div>
  <div><div><div v-if="foo"></div><div v-else-if></div></div></div>
  <div><div v-if="foo"></div><div v-else-if=""></div></div>
</template>
