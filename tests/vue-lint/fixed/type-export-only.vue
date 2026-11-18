<script lang="ts">
export default { name: 'TypeExportOnly' }
</script>

<script setup lang="ts">
interface Props { a: number }
export type { Props }
</script>
