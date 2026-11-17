<template>
  <div><div><div v-if="foo"></div><div v-else></div></div></div>
  <div><div><div v-if="foo"></div><div v-else-if="foo"></div><div v-else></div></div></div>
  <div>
    <c1 v-if="1" />
    <c2 v-else-if="1" />
    <c3 v-else />
</div>
  <div><template v-else><div></div></template></div>
  <div><div v-else></div></div>
  <div><div><div v-else></div></div></div>
  <div><div><div></div><div v-else></div></div></div>
  <div><div><div if="foo"></div><div v-else></div></div></div>
  <div><div><div v-if="foo"></div><div></div><div v-else></div></div></div>
  <div><div><div v-if="foo"></div><div v-else v-if="bar"></div></div></div>
  <div><div><div v-if="foo"></div><div v-else v-else-if="foo"></div></div></div>
  <div><div><div v-if="foo"></div><div v-else:aaa></div></div></div>
  <div><div><div v-if="foo"></div><div v-else.aaa></div></div></div>
  <div><div><div v-if="foo"></div><div v-else="foo"></div></div></div>
  <div><div v-if="foo"></div><div v-else="."></div></div>
  <div><div v-if="foo"></div><div v-else="/**/"></div></div>
  <div><div v-if="foo"></div><div v-else=""></div></div>
</template>
