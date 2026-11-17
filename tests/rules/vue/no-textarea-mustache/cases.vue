<template>
  <div><div><textarea v-model="text"></textarea></div></div>
  <div><div><Textarea>{{text}}</Textarea></div></div>
  <div><div><textarea>{{text}}</textarea></div></div>
  <div><div><textarea v-model="text">{{text}}</textarea></div></div>
  <div><div><textarea>{{text}} and {{text}}</textarea></div></div>
</template>
