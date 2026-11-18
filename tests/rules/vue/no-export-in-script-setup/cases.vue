<script lang="ts">
export const ok = 1
</script>
<script setup lang="ts">
export const a = 1
export function b() {}
export { ok as c }
export * from './x'
export default {}
</script>
