<template>
  <div
    id="a"
      class="b"
    :title="msg"
  >
    <span>{{ msg }}</span>
      <p>
      text
        </p>
    <!-- a comment -->
  <!-- misplaced -->
    <ul>
      <li
        v-for="(item, index) in items"
        :key="index"
        @click="
          select(item)
          ;log(index)
        "
      >
        {{
          item.name
            .toUpperCase()
        }}
      </li>
    </ul>
    <pre>
  keep
      as is
</pre>
    <textarea>
 raw </textarea>
    <input
      :value="cond
        ? a
        : b"
     />
    <comp :fn="(x: number) => {
      return x + 1
    }" :obj="{
      a: 1,
        b: [
          2,
          3
        ]
    }"/>
    {{ msg | upper }}
	<b>tab</b>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
const msg = ref('hello')
const items = ref([{ name: 'x' }])
const cond = true
const a = 1
const b = 2
function select(item: { name: string }) { return item }
function log(i: number) { return i }
</script>
