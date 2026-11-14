declare const reader: FileReader;
declare const blob: Blob;

// Reported.
reader.readAsText(blob);
reader.readAsArrayBuffer(blob);
reader['readAsText'](blob);

// Not reported.
reader.readAsText(blob, 'utf-8');
reader.readAsDataURL(blob);
reader?.readAsText(blob);
reader.readAsText?.(blob);
reader.readAsArrayBuffer();
export {};
