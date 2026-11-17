<template>
  <div><my-component><div /></my-component></div>
  <div><div /></div>
  <div><my-component :inline-template="foo"><div /></my-component></div>
  <div><my-component Inline-Template="foo"><div /></my-component></div>
  <div><my-component inline-template><div /></my-component></div>
  <div><my-component inline-template=""><div /></my-component></div>
  <div><my-component inline-template="foo"><div /></my-component></div>
</template>
