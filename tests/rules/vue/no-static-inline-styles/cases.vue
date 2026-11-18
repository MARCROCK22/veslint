<template>
  <div>
      <div class="hidden">
    </div>
  <div>
      <div :style="prop">
    </div>
  <div>
      <div :style="{
        backgroundImage: 'url('+data.img+')'
      }">
    </div>
  <div>
      <div :style="{
       [backgroundImage]: 'url(./img.png)'
      }" }>
    </div>
  <div>
      <div v-bind:style>
    </div>
  <div>
      <div :style="{
        [computed]: 'url(./img.png)',
        'background-image': 'url(./img.png)',
        color: 'red',
      }">
    </div>
  <div>
      <div :style="{
        ...spread,
        'background-image': 'url(./img.png)',
        color: 'red',
      }">
    </div>
  <div>
      <div :style="[
        { ...propStyle },
        { backgroundImage: 'url(./img.png)' },
      ]">
    </div>
  <div>
      <div v-bind:style="{
        'background-image': 'url(./img.png)'
        ">
    </div>
  <div>
        <div style="display: none;">
      </div>
  <div>
        <div style>
      </div>
  <div>
        <div :style="{
          backgroundImage: 'url(./img.png)'
        }">
      </div>
  <div>
        <div :style="{
          'background-image': 'url(./img.png)'
        }">
      </div>
  <div>
        <div v-bind:style="{
          'background-image': 'url(./img.png)'
        }">
      </div>
  <div>
        <div :style="{
          color: color,
          'background-image': 'url(./img.png)'
        }">
      </div>
  <div>
        <div :style="{
          'background-image': 'url(./img.png)',
          color,
        }">
      </div>
  <div>
        <div :style="[
          { 'background-image': 'url(./img.png)' },
          { color: 'red' }
        ]">
      </div>
  <div>
        <div :style="[
          { backgroundImage: 'url(./img.png)' },
          { ...propStyle },
          { backgroundImage: 'url(./img.png)' },
        ]">
      </div>
  <div>
        <div :style="[
          { backgroundImage: 'url(./img.png)' },
          { backgroundImage: 'url(./img.png)', color, font: 'xxx', },
          { backgroundImage: 'url(./img.png)' },
        ]">
      </div>
  <div>
        <div :style="[
          { backgroundImage: 'url(./img.png)' },
          ,
          { backgroundImage: 'url(./img.png)' },
        ]">
      </div>
  <div>
        <div :style="[
          { backgroundImage: 'url(./img.png)' },
          'string',
          { backgroundImage: 'url(./img.png)' },
        ]">
      </div>
</template>
