<template>
  <div>
        <div/>
        <slot></slot>
        <slot name="foo"></slot>
        <MyComponent><template #foo></template></MyComponent>
        <component :is="foo"></component>
        <transition></transition>
        <keep-alive></keep-alive>
      </div>
</template>
