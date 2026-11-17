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
        <!-- ignore -->
        <template foo="a">...</template>
        <template :foo="a">...</template>
        <template v-unknown="a">...</template>
      </div>
  <div>
        <div v-if="foo" class="heading">...</div>
        <div v-for="i in foo" :bar="i">...</div>
        <div v-slot:foo="foo" ref="input">...</div>
        <div v-if="foo" @click="click">...</div>
      </div>
  <div>
        <!-- ✓ GOOD -->
        <template v-if="foo">...</template>
        <template v-if="foo">...</template>
        <template v-else-if="foo">...</template>
        <template v-else>...</template>
        <template v-for="i in foo" :key="i">...</template>
        <template v-slot:foo>...</template>
        <!-- for Vue<=2.5 -->
        <template slot="foo">...</template>
        <template :slot="foo">...</template>
        <template slot-scope="param">...</template>
        <!-- for Vue<=2.4 -->
        <template scope="param">...</template>

        <!-- ✗ BAD -->
        <template v-if="foo" class="heading">...</template>
        <template v-for="i in foo" :bar="i">...</template>
        <template v-slot:foo="foo" ref="input">...</template>
        <template v-if="foo" @click="click">...</template>

        <!-- Ignore -->
        <template class="heading">...</template>
        <template :bar="i">...</template>
        <template ref="input">...</template>
        <template @click="click">...</template>
      </div>
</template>
