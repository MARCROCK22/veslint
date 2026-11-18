import { goto } from '$app/navigation';
import { resolve } from '$app/paths';
goto('/a');
goto(resolve('/about'));
