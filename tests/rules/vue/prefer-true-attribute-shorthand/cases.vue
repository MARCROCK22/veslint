<template>
  <div>
        <MyComp v-if="true" />
      </div>
  <div>
        <MyComp v-bind="true" />
      </div>
  <div>
        <MyComp v-loading="true" />
      </div>
  <div>
        <MyComp show="true" />
      </div>
  <div>
        <MyComp v-bind:show="value" />
      </div>
  <div>
        <MyComp :show="value" />
      </div>
  <div>
        <MyComp v-bind:show="false" />
      </div>
  <div>
        <MyComp :show="false" />
      </div>
  <div>
        <MyComp show />
      </div>
  <div>
        <input v-bind:checked="true" />
      </div>
  <div>
        <input :checked="true" />
      </div>
  <div>
        <input checked="checked" />
      </div>
  <div>
        <MyComp v-bind:show="true" />
      </div>
  <div>
        <MyComp :show="true" />
      </div>
</template>
