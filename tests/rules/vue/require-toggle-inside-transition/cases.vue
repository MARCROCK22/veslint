<template>
  <div><transition><div v-if="show" /></transition></div>
  <div><transition><div v-show="show" /></transition></div>
  <div><Transition><div v-if="show" /></Transition></div>
  <div><Transition><div v-show="show" /></Transition></div>
  <div><Transition><MyComp /></Transition></div>
  <div><Transition><component :is="component" /></Transition></div>
  <div><Transition><div :is="component" /></Transition></div>
  <div><svg height="100" width="100"><transition><circle v-if="show" /></transition></svg> </div>
  <div><svg height="100" width="100"><transition><MyComponent /></transition></svg> </div>
  <div><transition><template v-if="show"><div /></template></transition></div>
  <div><transition><slot /></transition></div>
  <div><transition><div :key="k" /></transition></div>
  <div><transition appear><div /></transition></div>
  <div><transition :appear="foo"><div /></transition></div>
  <div><transition :appear="true"><div /></transition></div>
  <div><transition><div /></transition></div>
  <div><Transition><div /></Transition></div>
  <div><transition><div /><div /></transition></div>
  <div><transition><div v-for="e in list" /></transition></div>
  <div><svg height="100" width="100"><transition><circle /></transition></svg> </div>
  <div><transition><template v-for="e in list"><div /></template></transition></div>
  <div><Transition>  <div /></Transition></div>
  <div><transition :appear="false"><div /></transition></div>
  <div><transition @appear="isLoaded"><div /></transition></div>
</template>
