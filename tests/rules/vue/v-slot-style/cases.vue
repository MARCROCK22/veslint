<template>
  <div>
        <my-component v-slot="data">
          <template #default></template>
          <template #foo></template>
        </my-component>
      </div>
  <div>
          <my-component #default="data"></my-component>
        </div>
  <div>
          <my-component v-slot:default="data"></my-component>
        </div>
  <div>
          <my-component>
            <template v-slot></template>
          </my-component>
        </div>
  <div>
          <my-component>
            <template v-slot:default></template>
          </my-component>
        </div>
  <div>
          <my-component>
            <template v-slot:foo></template>
          </my-component>
        </div>
  <div>
          <my-component>
            <template v-slot:[foo]></template>
          </my-component>
        </div>
</template>
