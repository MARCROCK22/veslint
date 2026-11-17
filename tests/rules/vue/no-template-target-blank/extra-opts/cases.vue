<template>
  <div>
    <a href="https://x" target="_blank">1</a>
    <a href="//x" target="_blank" rel="noopener">2</a>
    <a href="mailto:x" target="_blank" rel="NOOPENER noreferrer">3</a>
    <a href="/local" target="_blank">4</a>
    <a :href="x" target="_blank">5</a>
    <a v-bind:href="x" target="_blank" rel>6</a>
    <a href="a_b:c" target="_blank" :rel="r">7</a>
    <a href="https://x" target="_BLANK">8</a>
    <a href="https://x" :target="'_blank'">9</a>
    <a href=":x" target="_blank">10</a>
    <a href="https://x" rel="noopener" target="_blank" rel="noreferrer">11</a>
  </div>
</template>
