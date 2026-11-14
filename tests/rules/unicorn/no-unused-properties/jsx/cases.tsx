declare function use(...values: unknown[]): void;

export function Component() {
	const components = {Used: () => null, Unused: () => null};
	const nested = {group: {Item: () => null, Other: () => null}};
	use(<components.Used />, <nested.group.Item />);
}
