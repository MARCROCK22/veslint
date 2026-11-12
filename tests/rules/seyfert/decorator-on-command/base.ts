// Classes of another module of the project.
import { ComponentCommand, ModalCommand } from 'seyfert';

export abstract class ButtonBase extends ComponentCommand {}
export abstract class FormBase extends ModalCommand {}
export class NotACommand {}
