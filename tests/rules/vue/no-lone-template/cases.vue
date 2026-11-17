<template>
  <div>
        <template v-if="foo">...</template>
        <template v-else-if="bar">...</template>
        <template v-else>...</template>
      </div>
  <div>
        <template v-for="e in list">...</template>
      </div>
  <div>
        <template v-slot>...</template>
      </div>
  <div>
        <CoolButton>
         <template slot="foo">...</template>
        </CoolButton>
      </div>
  <div>
        <CoolButton>
         <template slot-scope="foo">...</template>
        </CoolButton>
      </div>
  <div>
        <CoolButton>
         <template scope="foo">...</template>
        </CoolButton>
      </div>
  <div>
        <template>...</template>
      </div>
</template>
