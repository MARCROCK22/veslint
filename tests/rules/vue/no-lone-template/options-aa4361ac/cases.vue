<template>
  <div>
        <template id="a">...</template>
      </div>
  <div>
        <template :id="a">...</template>
      </div>
  <div>
        <template ref="b">...</template>
      </div>
  <div>
        <template :ref="b">...</template>
      </div>
  <div>
        <template v-on:id="a">...</template>
      </div>
  <div>
        <template v-bind="id">...</template>
      </div>
  <div>
        <template v-bind:[foo]="id">...</template>
      </div>
  <div>
        <template class="b">...</template>
      </div>
</template>
