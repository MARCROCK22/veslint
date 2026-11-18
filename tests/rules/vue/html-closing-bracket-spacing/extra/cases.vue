<template>
  <div >
    <span a="1"/>
    <span a="1" /><!-- c -->
    <p
      a="1" ></p >
    <img src="x">
    <br/ >
    <MyComp :a="b"   />
    <MyComp :a="b"
    />
  </div  >
</template >
<script lang="ts">
const x = 1
</script>
