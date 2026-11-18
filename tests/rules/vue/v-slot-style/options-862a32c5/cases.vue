<template>
  <div>
          <template>
            <my-component v-slot:default="data">
              <template #default></template>
              <template #foo></template>
            </my-component>
          </template>
        </div>
  <div>
          <my-component #default="data"></my-component>
        </div>
  <div>
          <my-component v-slot="data"></my-component>
        </div>
</template>
