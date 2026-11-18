<template>
  <div>
        <MyComp show />
      </div>
  <div>
        <MyComp v-bind:show="true" />
      </div>
  <div>
        <MyComp :show="true" />
      </div>
</template>
