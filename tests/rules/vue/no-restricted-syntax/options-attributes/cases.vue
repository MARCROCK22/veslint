<template>
  <input :value="interpolate(foo, bar, false)">
  <input :value="interpolate(foo, bar, true)">
  <p>{{ $gettext(`bar`) }}</p>
</template>
