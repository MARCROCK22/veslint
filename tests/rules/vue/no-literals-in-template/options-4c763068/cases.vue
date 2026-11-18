<template>
  <div><MyComponent v-bind:slot-style="{ color: themeColor }" /></div>
  <div><MyComponent :slot-class="[{ active: isActive }]" /></div>
</template>
