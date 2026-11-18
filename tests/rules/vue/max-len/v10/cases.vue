
<script lang="ts">
var a // trailing comment .......................................................
var b /* comment */ // trailing comments ........................................
/* full line comment ......................................................... */
</script>
<template>
  <!-- HTML full line comment ............................................... -->
  <div class="foo"
       :class="{
         'foo': foo, // trailing comment ........................................
         'bar': bar, /* comment */ // trailing comments .........................
         /* full line comment ................................................ */
       }"> <!-- HTML trailing comment ....................................... -->
  </div> <!-- comment --><!-- HTML trailing comments ........................ -->
</template>
