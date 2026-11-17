<template>
  <div><div><div v-for="x in list" v-bind:key="x"></div></div></div>
  <div><div><div v-for="x in list" :key="x.foo"></div></div></div>
  <div><div><custom-component v-for="x in list"></custom-component></div></div>
  <div><div><template v-for="x in list"><div :key="x"></div></template></div></div>
  <div><div><slot v-for="x in list" :name="x"></slot></div></div>
  <div><div><slot v-for="x in list" :name="x"><div :key="x"></div></slot></div></div>
  <div><div><template v-for="x in list" v-bind:key="x"><div /></template></div></div>
  <div><div><template v-for="x in list" v-bind:key="x"><MyComp /></template></div></div>
  <div><div><template v-for="x in list" :key="x"><div /></template></div></div>
  <div><div><template v-for="x in list" :key="x"><MyComp /></template></div></div>
  <div><div><template v-for="x in list" :key="x.id"><div /></template></div></div>
  <div><div><template v-for="x in list" :key="x.id"><MyComp /></template></div></div>
  <div><div><template v-for="(x, i) in list" :key="i"><div /></template></div></div>
  <div><div><template v-for="(x, i) in list" :key="i"><MyComp /></template></div></div>
  <div><div><slot v-for="x in list" :key="x"><div /></slot></div></div>
  <div><div><slot v-for="x in list" :key="x"><MyComp /></slot></div></div>
  <div><div><div v-for="x in list"></div></div></div>
  <div><div><div v-for="x in list" key="100"></div></div></div>
  <div><div><template v-for="x in list"><div></div></template></div></div>
  <div><div><slot v-for="x in list" :name="x"><div></div></slot></div></div>
</template>
