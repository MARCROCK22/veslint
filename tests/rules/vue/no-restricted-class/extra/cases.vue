<template>
  <div>
    <div class=" forbidden  other" />
    <div :class="['forbidden', { 'forbidden other': x, [k]: y, forbidden: z, 'ok': 1, 2: 3 }, ...rest, `a ${b} forbidden`, 'x' + c + ' forbidden', 1, null, true]" />
    <div :class="`forbidden ${`nested forbidden`} ${'lit forbidden'}`" />
    <div :class="cond ? 'forbidden' : 'other'" />
    <div v-bind:class="{ forbidden }" />
    <div :class="'forbidden' - 1" />
    <div :[dyn]="'forbidden'" class="FORBIDDEN null 1" />
  </div>
</template>
