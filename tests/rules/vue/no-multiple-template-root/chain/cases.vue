<template>
  <div v-if="a">a</div>
  <template v-else-if="b">b</template>
  <slot v-else v-for="x in y" />
</template>
