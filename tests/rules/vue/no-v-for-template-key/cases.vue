<template>
  <div><template></template></div>
  <div><div key="foo"></div></div>
  <div><div v-bind:key="foo"></div></div>
  <div><div :key="foo"></div></div>
  <div><div><template key="foo"></template></div></div>
  <div><div><template v-bind:key="foo"></template></div></div>
  <div><div><template :key="foo"></template></div></div>
  <div><template v-slot="item" :key="item.id"><div /></template></div>
  <div><template v-for="item in list"><template :key="item.id"><div /></template></template></div>
  <div><template v-for="item in list" :key="item.id"><div /></template></div>
  <div><template v-for="(item, i) in list" :key="i"><div /></template></div>
  <div><template v-for="item in list" :key="foo + item.id"><div /></template></div>
  <div><template v-for="item in list" key="foo"><div /></template></div>
</template>
