<script setup lang="ts">
declare function doSomething(): Promise<void>
defineExpose({})
await doSomething()
defineExpose({})
</script>
