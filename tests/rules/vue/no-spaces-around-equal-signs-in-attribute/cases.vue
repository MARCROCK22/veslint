<template>
  <div><div attr="value" /></div>
  <div><div attr="" /></div>
  <div><div attr='value' /></div>
  <div><div attr=value /></div>
  <div><div attr /></div>
  <div><div/></div>
  <div>
      <div
        is="header"
        v-for="item in items"
        v-if="!visible"
        v-once
        id="uniqueID"
        ref="header"
        v-model="headerData"
        myProp="prop"
        @click="functionCall"
        v-text="textContent">
      </div>
    </div>
  <div><div attr = "value" /></div>
  <div><div attr = "" /></div>
  <div><div attr = 'value' /></div>
  <div><div attr = value /></div>
  <div><div attr 	
   =   	
 "value" /></div>
  <div><div attr ="value" /></div>
  <div><div attr= "value" /></div>
  <div>
          <div
            is = "header"
            v-for = "item in items"
            v-if = "!visible"
            v-once
            id = "uniqueID"
            ref = "header"
            v-model = "headerData"
            myProp = "prop"
            @click = "functionCall"
            v-text = "textContent">
          </div>
        </div>
</template>
