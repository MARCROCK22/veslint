<template>
  <div @click="const { my_pref } = $event" />
  <div @click="const { my_pref: my_pref } = $event" />
  <div @click="const { my_pref: other_name } = $event" />
  <div @click="const { my_pref = 1 } = $event; use(my_pref)" />
</template>
