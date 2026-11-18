<template>
  <div>
          <template>
            <my-component #default="data">
              <template #default></template>
              <template #foo></template>
            </my-component>
          </template>
        </div>
  <div>
          <my-component v-slot:default="data"></my-component>
        </div>
  <div>
          <my-component v-slot="data"></my-component>
        </div>
</template>
