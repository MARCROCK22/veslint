<template>
  <div>
      <div is="vue:MyComponent" />
    </div>
  <div>
      <component is="MyComponent" />
    </div>
  <div>
        <div v-is="'MyComponent'" />
      </div>
</template>
