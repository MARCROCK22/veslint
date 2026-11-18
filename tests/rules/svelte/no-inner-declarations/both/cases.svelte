<script lang="ts" module>
	export function top() {}
	var moduleVar = 1;
	if (moduleVar) {
		function inner() {}
		inner();
	}
</script>

<script lang="ts">
	function instance() {}
	var instanceVar = 1;
	if (instanceVar) {
		function nested() {}
		var nestedVar = 2;
		nested();
		nestedVar;
	}
	instance();
</script>
