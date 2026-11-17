<template>
  <div>
          <template>
            <my-component v-slot="data">
              <template v-slot></template>
              <template #foo></template>
            </my-component>
          </template>
        </div>
  <div>
          <my-component>
            <template #default></template>
          </my-component>
        </div>
  <div>
          <my-component>
            <template v-slot:default></template>
          </my-component>
        </div>
</template>
