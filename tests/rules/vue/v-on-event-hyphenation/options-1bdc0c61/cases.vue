<template>
  <div>
          <VueComponent v-on:custom-event="events"/>
      </div>
  <div>
        <VueComponent @update:modelValue="foo"/>
        <VueComponent @update:model-value="foo"/>
      </div>
  <div>
        <VueComponent @upDate:modelValue="foo"/>
        <VueComponent @up-date:modelValue="foo"/>
        <VueComponent @upDate:model-value="foo"/>
        <VueComponent @up-date:model-value="foo"/>
      </div>
</template>
