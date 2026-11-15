declare const UI: { Button: () => null; Deep: { Item: () => null } };

const a = <UI.Button />;
const b = <UI.
	Button />;
const c = <UI
	.Button />;
const d = <UI.Deep
	.Item></UI.Deep
	.Item>;
const e = UI
	.Button;
