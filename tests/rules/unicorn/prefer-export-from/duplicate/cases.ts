// unicorn/prefer-export-from: an import with two definitions is not checked.
import {twice} from 'first-module';
import {twice} from 'second-module';
export {twice};

import {single} from 'single-module';
export {single};
