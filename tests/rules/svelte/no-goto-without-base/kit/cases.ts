import { goto } from '$app/navigation';
import { base } from '$app/paths';

goto('/foo');
goto(`${base}/foo`);
