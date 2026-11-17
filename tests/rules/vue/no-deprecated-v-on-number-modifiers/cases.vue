<template>
  <div><input v-on:keyup.page-down='onArrowUp'></div>
  <div><input @keyup.page-down='onArrowUp'></div>
  <div><input v-on:keyup.9='onArrowUp'></div>
  <div><input @keyup.9='onArrowUp'></div>
  <div><input v-on:keyup.0='onArrowUp'></div>
  <div><input @keyup.0='onArrowUp'></div>
  <div><input v-on:keyup.4='onArrowUp'></div>
  <div><input @keyup.4='onArrowUp'></div>
  <div><input v-on:keyup.page-down.native='onArrowUp'></div>
  <div><input @keyup.page-down.native='onArrowUp'></div>
  <div><input v-on:keyup.0.native='onArrowUp'></div>
  <div><input @keyup.0.native='onArrowUp'></div>
  <div><input v-on:keyup.34='onArrowUp'></div>
  <div><input v-on:keyup.34.native='onArrowUp'></div>
  <div><input v-on:keyup.unknown.34='onArrowUp'></div>
  <div><input v-on:[dynamicArg].34='onArrowUp'></div>
  <div><input v-on:[dynamicArg].unknown.34='onArrowUp'></div>
  <div><input v-on:[dynamicArg].34.unknown='onArrowUp'></div>
  <div><input @keyup.34='onArrowUp'></div>
  <div><input @keyup.34.native='onArrowUp'></div>
  <div><input @keyup.unknown.34='onArrowUp'></div>
  <div><input @[dynamicArg].34='onArrowUp'></div>
  <div><input @[dynamicArg].unknown.34='onArrowUp'></div>
  <div><input @[dynamicArg].34.unknown='onArrowUp'></div>
  <div><input @keyup.10='onArrowUp'></div>
  <div><input @keyup.10.native='onArrowUp'></div>
  <div><input @keyup.unknown.10='onArrowUp'></div>
  <div><input @[dynamicArg].unknown.10='onArrowUp'></div>
  <div>
        <input @keydown.48='onKeydown'>
        <input @keydown.57='onKeydown'>
        <input @keydown.91='onKeydown'>
        <input @keydown.92='onKeydown'>
        <input @keydown.93='onKeydown'>
        <input @keydown.96='onKeydown'>
        <input @keydown.111='onKeydown'>
      </div>
  <div>
        <input @keydown.19='onKeydown'>
        <input @keydown.37='onKeydown'>
        <input @keydown.38='onKeydown'>
        <input @keydown.39='onKeydown'>
        <input @keydown.40='onKeydown'>
      </div>
</template>
