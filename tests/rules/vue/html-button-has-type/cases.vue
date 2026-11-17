<template>
  <div><button type="button">Hello World</button></div>
  <div><button type="submit">Hello World</button></div>
  <div><button type="reset">Hello World</button></div>
  <div><slot><button type="button">Hello World</button></slot></div>
  <div>
                <button type="button">Hello World</button>
                <button type="submit">Hello World</button>
                <button type="reset">Hello World</button>
             </div>
  <div><button :type="buttonType">Hello World</button></div>
  <div><Button>Hello World</Button></div>
  <div><button>Hello World</button></div>
  <div><button type="">Hello World</button></div>
  <div><button type>Hello World</button></div>
  <div><button type="foo">Hello World</button></div>
  <div><button>Hello World</button><button>Hello World</button></div>
  <div><button :type="">Hello World</button></div>
</template>
