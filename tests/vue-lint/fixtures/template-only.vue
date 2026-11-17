<template>
  <div class="box">   
    <span>{{ message }}</span>
  </div>
</template>

<style scoped>
.box { color: v-bind(color); }
</style>
