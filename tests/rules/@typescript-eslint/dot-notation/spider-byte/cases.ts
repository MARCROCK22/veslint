// dot-notation with the options of Spider-Byte's configuration (equal to the defaults).
declare const env: Record<string, string | undefined>;
declare const settings: { theme: string; 'dark-mode': boolean };

// Reported.
env['TOKEN'];
settings['theme'];

// Not reported.
settings['dark-mode'];
env.TOKEN;
