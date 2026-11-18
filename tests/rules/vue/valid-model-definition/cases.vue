<script lang="ts">
export default {
  model: {
    prop: 'checked',
    event: 'change',
    props: 'x',
    events: 'y',
    'other': 1,
    [`tpl`]: 2,
    ...{ spread: 3 },
    '': 4,
  },
}
</script>
