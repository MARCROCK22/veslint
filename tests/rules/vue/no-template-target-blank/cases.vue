<template>
  <div><a>link</a></div>
  <div><a attr>link</a></div>
  <div><a target>link</a></div>
  <div><a href="https://eslint.vuejs.org">link</a></div>
  <div><a :href="link">link</a></div>
  <div><a :href="link" target="_blank" rel="noopener noreferrer">link</a></div>
  <div><a href="https://eslint.vuejs.org" target="_blank" rel="noopener noreferrer">link</a></div>
  <div><a href="/foo" target="_blank">link</a></div>
  <div><a href="/foo" target="_blank" rel="noopener noreferrer">link</a></div>
  <div><a href="foo/bar" target="_blank">link</a></div>
  <div><a href="foo/bar" target="_blank" rel="noopener noreferrer">link</a></div>
  <div><a href="https://eslint.vuejs.org" target="_blank">link</a></div>
  <div><a href="https://eslint.vuejs.org" target="_blank" rel="noopenernoreferrer">link</a></div>
  <div><a :href="link" target="_blank" rel=3>link</a></div>
  <div><a :href="link" target="_blank">link</a></div>
  <div><a href="https://eslint.vuejs.org" target="_blank" rel="noopener">link</a></div>
</template>
