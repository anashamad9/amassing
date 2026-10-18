const repo = 'https://github.com/anashamad9/amassing';
const release = `${repo}/releases/tag/v0.6.2-beta.1`;

function AppleMark() {
  return <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M16.5 12.8c0-2 1.6-3 1.7-3.1-1-1.5-2.5-1.7-3.1-1.7-1.3-.1-2.5.8-3.2.8-.6 0-1.6-.8-2.7-.7-1.4 0-2.7.8-3.4 2-1.5 2.6-.4 6.4 1 8.4.7 1 1.4 2 2.5 1.9 1-.1 1.4-.6 2.7-.6s1.7.6 2.8.6c1.2 0 1.9-1 2.5-1.9.8-1.1 1.1-2.2 1.2-2.3-.1 0-2-.8-2-3.4Zm-2.1-6c.5-.7.9-1.6.8-2.6-.8 0-1.8.5-2.4 1.2-.5.6-1 1.6-.9 2.5.9.1 1.9-.4 2.5-1.1Z" /></svg>;
}
export default function Home() {
  return (
    <main>
      <nav aria-label="Main navigation"><a href={repo} className="wordmark">↖ anasing<span>.app</span></a><a className="source" href={repo}>Open source ↗</a></nav>
      <section className="hero" aria-labelledby="headline">
        <div className="intro">
          <div className="app-icon"><img src="/icon.svg" width="80" height="80" alt="Anasing app icon" /><span className="platform"><AppleMark /></span></div>
          <p className="badge"><span />Now in beta · October 2026</p>
          <h1 id="headline">A little shortcut.<br />For every file.</h1>
          <p className="description">Meet Anasing. Drag a file, tap a key, and convert, edit, or move it right where you are. A small glass toolbar for your Mac, with English and Arabic side by side.</p>
          <p className="arabic" lang="ar" dir="rtl">اسحب ملفك. اضغط مفتاحاً. والباقي على أناسينغ.</p>
          <div className="buttons"><a className="download" href={release}><AppleMark />Download for Mac <span>↗</span></a><span className="chip">Apple silicon</span><a className="docs" href={`${repo}#readme`}>Read the docs ↗</a></div>
          <p className="requirements">macOS 26.6.2+ · Free & open source · No account</p>
          <p className="beta-note">Unsigned beta. macOS may require additional approval to open.</p>
        </div>
        <div className="scene" aria-label="Anasing action bar demo">
          <div className="scene-top"><span className="lights"><i/><i/><i/></span><span>A quieter way to get things done.</span><span>⌘</span></div>
          <div className="workspace">
            <div className="shortcut"><kbd>⇧</kbd> Convert <span>·</span> <kbd>⌘</kbd> Tools <span>·</span> <kbd>⌃</kbd> Actions</div>
            <div className="toolbar-wrap"><img className="toolbar" src="/actions.png" alt="Compact glass toolbar: AirDrop, Float, Copy, Move, Copy Path, and Terminal, each labeled in English and Arabic." /></div>
            <div className="file"><div className="file-image"><span className="sun"/><span className="hill back"/><span className="hill front"/></div><span>weekend.png</span></div>
            <svg className="cursor" width="30" height="38" viewBox="0 0 30 38" aria-hidden="true"><path d="M5 3v28l8-7 7 12 6-4-8-12 10-3Z" fill="#fff" stroke="#25252b" strokeWidth="2" strokeLinejoin="round"/></svg>
            <div className="scene-caption"><span className="dot"/>Your files stay on your Mac. New copies stay beside the original.</div>
          </div>
          <div className="scene-bottom"><span>Made for the flow.</span><span lang="ar" dir="rtl">خطوة أقل، إنجاز أكثر.</span></div>
        </div>
        <footer><span>Anasing · أناسينغ</span><span>Built by <a href="https://github.com/anashamad9">Anas Hamad</a> · AGPL-3.0</span></footer>
      </section>
    </main>
  );
}
