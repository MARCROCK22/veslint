<template>
  <div><input v-on:keyup.enter='fire'></div>
  <div><input @keyup.enter='fire'></div>
  <div><input v-native:foo.native.foo.bar='fire'></div>
  <div><input @native.enter='fire'></div>
  <div><input :keydown.native='fire'></div>
  <div><input v-on:keyup.native='fore'></div>
  <div><input v-on:keyup.foo.native.bar='fore'></div>
</template>
