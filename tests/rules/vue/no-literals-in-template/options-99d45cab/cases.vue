<template>
  <div><MyComponent :slot-class="[{ active: isActive }]" /></div>
  <div><MyComponent :wrapper-class="[{ active: isActive }]" /></div>
</template>
