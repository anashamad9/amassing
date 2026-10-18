import type { Metadata } from 'next';
import './globals.css';
export const metadata: Metadata = {
  title: 'Anasing — a little shortcut for every file.',
  description: 'Drag a file, tap a key, and make it yours. A quiet macOS utility for conversions and quick edits, in English and Arabic.',
  icons: { icon: '/icon.svg' },
};
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
