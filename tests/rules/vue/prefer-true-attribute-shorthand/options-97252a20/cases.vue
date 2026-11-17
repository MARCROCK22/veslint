<template>
  <div>
        <MyComp :show="true" />
      </div>
  <div>
        <MyComp v-bind:show="true" />
      </div>
  <div>
        <input checked />
      </div>
  <div>
        <MyComp show />
      </div>
</template>
