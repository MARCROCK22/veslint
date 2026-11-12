// `jsx: "react-jsx"`: typescript-eslint 8.62.0's parser does not look at the option, so the
// element still references a `React` in its scopes.
import React from 'react';
export const a = <div />;
export const b = <></>;
