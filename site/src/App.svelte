<script>
  import logo from '../../assets/brand/wisp_icon.svg';

  const repo = 'https://github.com/domeepc/wisp';
  // The web app, built next to this site (see .github/workflows/pages.yml).
  const webApp = 'app/';

  // The files of the latest release. Their names carry the version, so
  // they're looked up; until then (or if GitHub says no) the buttons go to
  // the release page.
  let assets = $state([]);
  fetch('https://api.github.com/repos/domeepc/wisp/releases/latest')
    .then((r) => r.json())
    .then((r) => (assets = r.assets ?? []))
    .catch(() => {});
  const fileUrl = (ending) =>
    assets.find((a) => a.name.endsWith(ending))?.browser_download_url ?? `${repo}/releases/latest`;

  // ponytail: builds without a real signature are off (no files) until
  // signing is set up in release.yml; list a file ending to turn one on
  // (Android '.apk', macOS '.dmg', Windows '-setup.exe').
  const downloads = [
    { name: 'iPhone & iPad', note: 'App Store', files: [] },
    { name: 'Android', note: 'APK', files: [] },
    { name: 'macOS', note: 'Apple silicon & Intel · .dmg', files: [] },
    { name: 'Windows', note: 'Installer · .exe', files: [] },
    { name: 'Linux', note: 'Debian, Ubuntu or any distro', files: ['.deb', '.tar.gz'] },
  ];

  const steps = [
    ['Open Wisp on both devices', 'Same Wi-Fi or hotspot is all it needs. Devices find each other on their own.'],
    ['Pick what to send', 'Files, photos, a whole folder, some text, a voice note or whatever is on your clipboard.'],
    ['Tap the device', 'The other side taps Accept, and the files are saved on their device.'],
  ];

  const features = [
    ['wifi', 'Stays on your network', 'No uploads, no cloud copies. Works on a phone hotspot too.'],
    ['no_accounts', 'No account', 'Nothing to sign up for. Open the app and you are ready to send.'],
    ['bolt', 'Full Wi-Fi speed', 'Transfers run as fast as your network allows, with no size limit.'],
    ['lock', 'Encrypted and verified', 'Every transfer is encrypted, and a short security code shows who is sending.'],
    ['folder', 'Any file, any folder', 'Photos keep their quality, folders keep their structure, text goes to the clipboard.'],
    ['check', 'Trusted devices', 'Tick "Always accept" once and your own devices send without asking.'],
  ];

  const faq = [
    ['Do I need internet?', 'Yes. Wisp uses the internet to find your devices and connect them. The files themselves go straight from one device to the other whenever the network allows.'],
    ['Does the other person need Wisp?', 'No. They can open Wisp in any web browser, on the same Wi-Fi as you.'],
    ['Is there a file size limit?', 'No. Send a single photo or a 50 GB folder the same way.'],
    ["Why can't I see my other device?", 'Check both are on the same network and Wisp is open. On guest or school Wi-Fi, devices often can\'t see each other: use Connect with code, or a phone hotspot.'],
  ];

  const nearby = [
    ['laptop', 'MacBook Pro', 'macOS'],
    ['desktop_windows', 'Living room PC', 'Windows'],
    ['smartphone', "Ana's Pixel 8", 'Android'],
  ];
</script>

{#snippet icon(name)}<span class="icon" aria-hidden="true">{name}</span>{/snippet}

{#snippet wordmark(size = 34)}
  <span class="wordmark" style="--s: {size}px"><img src={logo} alt="" />Wisp</span>
{/snippet}

<header class="wrap nav">
  <a href="./" aria-label="Wisp home">{@render wordmark(28)}</a>
  <nav>
    <a href="#how">How it works</a>
    <a href="#features">Features</a>
    <a href="#faq">FAQ</a>
    <a href={webApp}>Open in browser</a>
    <a class="btn dark small" href="#download">Download</a>
  </nav>
</header>

<main>
  <section class="wrap hero">
    <div>
      <p class="pill">Phone, laptop, PC, browser</p>
      <h1>Send files to the device next to you.</h1>
      <p class="lead">
        Wisp moves photos, videos and documents between your devices over your own Wi-Fi.
        No cloud, no account, no cables.
      </p>
      <div class="row">
        <a class="btn" href="#download">{@render icon('download')} Download Wisp</a>
        <a class="btn outline" href={webApp}>Try it in the browser</a>
      </div>
      <p class="fine">For Android, macOS, Windows, Linux and any web browser.</p>
    </div>

    <div class="stage" aria-hidden="true">
      <!-- The app's phone home screen (lib/screens/home_screen.dart). -->
      <div class="phone">
        <div class="app">
          <div class="status"><span>9:41</span><i></i>{@render icon('wifi')}</div>
          <div class="app-row">{@render wordmark()}<span class="spacer"></span>{@render icon('settings')}</div>
          <div class="card this-device">
            <span class="avatar blue">{@render icon('smartphone')}</span>
            <div class="grow">
              <b>Ana's iPhone</b>
              <span class="dot green">Visible · ready to receive</span>
            </div>
            <span class="switch"></span>
          </div>
          <p class="label">Send</p>
          <div class="tiles">
            {#each [['insert_drive_file', 'Files'], ['image', 'Photos'], ['notes', 'Text'], ['content_paste', 'Paste'], ['mic', 'Voice']] as [i, t], n}
              <span class="tile" class:primary={n === 0}>{@render icon(i)}{t}</span>
            {/each}
          </div>
          <p class="label">Nearby · 3 <span class="dot blue">Scanning Wi-Fi</span></p>
          <div class="card list">
            {#each nearby as [i, name, platform]}
              <div class="tile-row">
                <span class="avatar">{@render icon(i)}</span>
                <div class="grow"><b>{name}</b><small>{platform}</small></div>
                {@render icon('chevron_right')}
              </div>
            {/each}
          </div>
          <div class="banner">
            <span class="avatar solid">{@render icon('upload')}</span>
            <div class="grow"><b>Sending 12 photos to MacBook Pro</b><small>72% · 38 MB/s</small></div>
            <b class="accent">Open</b>
          </div>
        </div>
      </div>

      <!-- A toast on the receiving laptop (lib/widgets/toasts.dart). -->
      <div class="toast">
        <span class="avatar blue">{@render icon('laptop')}</span>
        <div class="grow">
          <b>Receiving 12 photos from Ana's iPhone</b>
          <small>9 of 12 photos · 38 MB/s</small>
          <span class="bar"><span></span></span>
        </div>
      </div>
    </div>
  </section>

  <section class="wrap strip">
    <span class="fine">Works across</span>
    <!-- Icons as in the app's DevicePlatform (lib/models/device.dart). -->
    {#each [['smartphone', 'Android'], ['laptop', 'macOS'], ['desktop_windows', 'Windows'], ['desktop_windows', 'Linux'], ['language', 'Any web browser']] as [i, p]}
      <b>{@render icon(i)}{p}</b>
    {/each}
  </section>

  <section class="wrap" id="how">
    <p class="eyebrow">How it works</p>
    <h2>Three taps. Nothing to set up.</h2>
    <div class="grid">
      {#each steps as [title, body], i}
        <div class="card box"><span class="num">{i + 1}</span><h3>{title}</h3><p>{body}</p></div>
      {/each}
    </div>
  </section>

  <section class="wrap" id="features">
    <p class="eyebrow">Why Wisp</p>
    <div class="split">
      <h2>Private by design, fast by default.</h2>
      <p>Your files travel straight from one device to the other and are never stored on a server.</p>
    </div>
    <div class="grid">
      {#each features as [i, title, body]}
        <div class="card box"><span class="chip">{@render icon(i)}</span><h3>{title}</h3><p>{body}</p></div>
      {/each}
    </div>
  </section>

  <section class="wrap">
    <div class="browser-band">
      <div>
        <p class="eyebrow">No install on the other side</p>
        <h2>A friend without Wisp? Just open a browser.</h2>
        <p>
          Anyone on your Wi-Fi can open Wisp in their browser to send you files or get yours.
          Nothing to install, and nothing left behind when they close the tab.
        </p>
        <a class="btn dark small" href={webApp}>Open Wisp in the browser</a>
      </div>

      <!-- The web app at desktop width (lib/screens/desktop_home.dart). -->
      <div class="window" aria-hidden="true">
        <div class="chrome"><i></i><i></i><i></i><span>domeepc.github.io/wisp/app/</span></div>
        <div class="app desktop" style="zoom: 0.5">
          <aside>
            <div class="app-row">{@render wordmark()}<span class="spacer"></span>{@render icon('settings')}</div>
            <div class="card this-device muted">
              <span class="avatar blue">{@render icon('language')}</span>
              <div class="grow"><b>Browser · Chrome</b><span class="dot green">Connected to 1 device</span></div>
              <span class="switch"></span>
            </div>
            <div class="drop">
              <span class="chip round">{@render icon('upload')}</span>
              <b>Drop files or folders here</b>
              <small>then click a device to send</small>
              <div class="row center">
                <span class="btn dark">Choose files</span><span class="btn outline">Send text</span>
              </div>
            </div>
            <p class="label">Selected · 2.4 MB <span class="accent">Clear</span></p>
            <div class="card file"><span class="badge">PDF</span><span class="grow">report.pdf</span><small>2.4 MB</small></div>
          </aside>
          <div class="main">
            <h4>Nearby devices</h4>
            <span class="dot blue">Connected to 1 device</span>
            <div class="card device">
              <span class="avatar big">{@render icon('laptop')}</span>
              <b>MacBook Pro</b><small>macOS</small>
              <span class="btn">Send 1 file</span>
            </div>
            <p class="label">Transfers</p>
            <div class="card tile-row">
              <span class="avatar green">{@render icon('check')}</span>
              <div class="grow"><b>Sent vacation.zip to MacBook Pro</b><small>2 min ago · 180 MB</small></div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </section>

  <section class="get" id="download">
    <div class="wrap">
      <h2>Get Wisp</h2>
      <p>Install it on every device you own. They'll find each other.</p>
      <div class="grid">
        {#each downloads as d}
          <div class="dl" class:off={!d.files.length}>
            <div><b>{d.name}</b><small>{d.note}</small></div>
            <span class="row">
              {#each d.files as f}
                <a class="btn white small" href={fileUrl(f)}>{d.files.length > 1 ? f : 'Download'}</a>
              {:else}
                <span class="btn white small" aria-disabled="true">Coming soon</span>
              {/each}
            </span>
          </div>
        {/each}
        <div class="dl">
          <div><b>Browser</b><small>Nothing to install</small></div>
          <a class="btn white small" href={webApp}>Open</a>
        </div>
      </div>
    </div>
  </section>

  <section class="wrap split" id="faq">
    <div><p class="eyebrow">FAQ</p><h2>Good to know</h2></div>
    <dl>
      {#each faq as [q, a]}<dt>{q}</dt><dd>{a}</dd>{/each}
    </dl>
  </section>
</main>

<footer class="wrap">
  {@render wordmark(22)}
  <span class="fine">Send files to devices on your Wi-Fi. <a href={repo}>Source on GitHub</a></span>
</footer>

<style>
  /* The app's fonts and colors (assets/fonts, lib/theme/tokens.dart). */
  @font-face { font-family: 'Inter Tight'; font-weight: 700; src: url('../../assets/fonts/InterTight-Bold.ttf'); }
  @font-face { font-family: 'Inter Tight'; font-weight: 800; src: url('../../assets/fonts/InterTight-ExtraBold.ttf'); }
  @font-face { font-family: 'IBM Plex Sans'; font-weight: 400; src: url('../../assets/fonts/IBMPlexSans-Regular.ttf'); }
  @font-face { font-family: 'IBM Plex Sans'; font-weight: 600; src: url('../../assets/fonts/IBMPlexSans-SemiBold.ttf'); }

  :global(:root) {
    --bg: #f3f2ee; --surface: #fff; --muted: #eeede8; --border: #e6e2da; --border-strong: #cfc9bd;
    --text: #1a1a1c; --text-2: #6b6b70; --accent: #2f4bff; --accent-soft: #e7ebfd;
    --success: #1f7a4d; --success-soft: #e6f0ea; --danger: #b3261e; --danger-soft: #f8e3df;
    --dark: #17181c; --ease-out: cubic-bezier(0.23, 1, 0.32, 1);
  }
  :global(html) { scroll-behavior: smooth; }
  @media (prefers-reduced-motion: reduce) {
    :global(html) { scroll-behavior: auto; }
  }
  :global(body) {
    margin: 0; background: var(--bg); color: var(--text);
    font: 16px/1.55 'IBM Plex Sans', system-ui, sans-serif;
  }
  :global(*) { box-sizing: border-box; }
  a { color: inherit; text-decoration: none; }
  h1, h2, h3, h4 { font-family: 'Inter Tight', sans-serif; letter-spacing: -0.02em; line-height: 1.08; margin: 0; }
  h1 { font-size: clamp(44px, 6vw, 72px); font-weight: 800; letter-spacing: -0.035em; }
  h2 { font-size: clamp(32px, 4vw, 46px); font-weight: 800; }
  h3 { font-size: 18px; margin: 12px 0 8px; font-family: 'IBM Plex Sans'; font-weight: 600; letter-spacing: 0; }
  p { margin: 0; }
  small { display: block; color: var(--text-2); font-size: 13px; }
  section { padding: 56px 0; }

  .wrap { max-width: 1200px; margin: 0 auto; padding-left: 20px; padding-right: 20px; }
  .row { display: flex; gap: 12px; flex-wrap: wrap; align-items: center; }
  .center { justify-content: center; }
  .grow { flex: 1; min-width: 0; }
  .spacer { flex: 1; }
  .fine { font-size: 13px; color: var(--text-2); }
  .accent { color: var(--accent); }
  .icon { font-family: 'Material Symbols Outlined'; font-size: 22px; line-height: 1; font-feature-settings: 'liga'; user-select: none; }

  .wordmark {
    display: inline-flex; align-items: center; gap: calc(var(--s) * 0.3);
    font: 800 calc(var(--s) * 0.9) 'Inter Tight'; letter-spacing: calc(var(--s) * -0.05);
  }
  .wordmark img { width: var(--s); height: var(--s); }

  .btn {
    display: inline-flex; align-items: center; gap: 8px; height: 48px; padding: 0 22px;
    border-radius: 14px; background: var(--accent); color: #fff; font-weight: 600; font-size: 15px;
    border: 1px solid transparent; white-space: nowrap;
  }
  .btn .icon { font-size: 20px; }
  .btn.outline { background: var(--surface); color: var(--text); border-color: var(--border); }
  .btn.dark { background: var(--text); }
  .btn.white { background: #fff; color: var(--text); }
  .btn.small { height: 38px; padding: 0 16px; font-size: 14px; border-radius: 10px; }
  .btn[aria-disabled] { background: transparent; color: #fff9; border-color: #ffffff2e; }

  .nav { display: flex; align-items: center; justify-content: space-between; padding-top: 22px; padding-bottom: 22px; }
  .nav nav { display: flex; align-items: center; gap: 28px; font-size: 14px; font-weight: 600; }

  .hero { display: grid; grid-template-columns: 1.1fr 1fr; gap: 48px; align-items: center; padding-top: 48px; }
  .pill {
    display: inline-block; background: var(--accent-soft); color: var(--accent); font-size: 12px; font-weight: 600;
    padding: 4px 12px; border-radius: 99px; margin-bottom: 20px;
  }
  .pill::before { content: '●'; margin-right: 6px; font-size: 9px; vertical-align: 2px; }
  .lead { font-size: 18px; color: var(--text-2); margin: 24px 0 32px; max-width: 520px; }
  .hero .fine { margin-top: 20px; }

  .stage { position: relative; min-height: 700px; display: flex; justify-content: flex-start; align-items: center; }
  .stage::before {
    content: ''; position: absolute; width: 520px; height: 520px; border-radius: 50%;
    background: #e9e4da; right: -60px; top: 20px;
  }
  /* An iPhone-sized screen (390 × 844) at --z. */
  .phone {
    --z: 0.72; flex: none; box-sizing: content-box; width: calc(390px * var(--z)); height: calc(844px * var(--z));
    position: relative; border: 10px solid var(--dark); border-radius: 50px; overflow: hidden;
    background: var(--bg); box-shadow: 0 30px 60px -20px #0003;
  }
  .toast {
    position: absolute; right: -30px; bottom: 10px; width: 290px; display: flex; gap: 12px;
    background: var(--surface); border: 1px solid var(--border); border-radius: 20px; padding: 16px;
    box-shadow: 0 18px 40px -12px #0003; font-size: 13px; line-height: 1.35;
  }
  .toast small { font-size: 12px; margin-top: 2px; }
  .bar { display: block; height: 4px; background: var(--border); border-radius: 2px; margin-top: 10px; }
  .bar span { display: block; width: 75%; height: 100%; background: var(--accent); border-radius: 2px; }

  /* Mockups of the app, at the app's real sizes, shrunk with zoom. */
  .app { padding: 20px; font-size: 14px; line-height: 1.35; text-align: left; }
  .app b { font-weight: 600; display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .phone .app { zoom: var(--z); height: 844px; display: flex; flex-direction: column; padding-top: 0; }
  .status { display: flex; justify-content: space-between; align-items: center; height: 54px; padding: 0 16px; font-weight: 600; font-size: 16px; }
  .status i { width: 120px; height: 34px; border-radius: 20px; background: var(--dark); }
  .status .icon { font-size: 18px; }
  .app-row { display: flex; align-items: center; margin: 8px 0 20px; }
  .card { background: var(--surface); border: 1px solid var(--border); border-radius: 24px; }
  .this-device { display: flex; align-items: center; gap: 16px; padding: 16px; }
  .this-device b { font-size: 16px; }
  .this-device.muted { background: var(--bg); border-color: transparent; }
  .avatar {
    width: 40px; height: 40px; border-radius: 50%; flex: none; display: grid; place-items: center; background: var(--muted);
  }
  .avatar .icon { font-size: 18px; }
  .avatar.blue { width: 48px; height: 48px; background: var(--accent-soft); color: var(--accent); }
  .avatar.big { width: 48px; height: 48px; margin-bottom: 20px; }
  .avatar.solid { width: 36px; height: 36px; background: var(--accent); color: #fff; }
  .avatar.green { background: var(--success-soft); color: var(--success); }
  .dot { display: inline-flex; align-items: center; gap: 8px; color: var(--text-2); font-size: 14px; font-weight: 400; letter-spacing: 0; text-transform: none; }
  .dot::before { content: ''; width: 8px; height: 8px; border-radius: 50%; background: var(--success); }
  .dot.blue::before { background: var(--accent); }
  .switch { width: 52px; height: 32px; border-radius: 16px; background: var(--accent); position: relative; flex: none; }
  .switch::after { content: ''; position: absolute; right: 4px; top: 4px; width: 24px; height: 24px; border-radius: 50%; background: #fff; }
  .label {
    display: flex; justify-content: space-between; align-items: center; margin: 28px 0 12px;
    font-size: 12px; font-weight: 600; letter-spacing: 1.2px; text-transform: uppercase; color: var(--text-2);
  }
  .tiles { display: flex; gap: 8px; }
  .tile {
    flex: 1; height: 76px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px;
    background: var(--surface); border: 1px solid var(--border); border-radius: 14px; font-weight: 600; font-size: 13px;
  }
  .tile.primary { background: var(--accent); color: #fff; border-color: var(--accent); }
  .tile-row { display: flex; align-items: center; gap: 16px; padding: 12px 16px; }
  .list .tile-row + .tile-row { border-top: 1px solid var(--border); }
  .tile-row b { font-size: 16px; }
  .banner {
    display: flex; align-items: center; gap: 12px; margin-top: auto; padding: 12px 16px;
    background: var(--accent-soft); border-radius: 24px;
  }

  .desktop { display: flex; padding: 0; height: 740px; width: 1100px; }
  .desktop aside { width: 400px; background: var(--surface); border-right: 1px solid var(--border); padding: 28px; }
  .desktop .main { flex: 1; padding: 44px; }
  .desktop h4 { font-size: 30px; }
  .drop {
    margin-top: 20px; padding: 44px 20px; border: 2px dashed var(--border-strong); border-radius: 24px; text-align: center;
  }
  .drop b { font-size: 16px; margin-top: 16px; }
  .drop .row { margin-top: 16px; }
  .chip { width: 40px; height: 40px; border-radius: 12px; display: grid; place-items: center; background: var(--accent-soft); color: var(--accent); }
  .chip.round { width: 56px; height: 56px; border-radius: 50%; margin: 0 auto; }
  .file { display: flex; align-items: center; gap: 12px; padding: 8px 12px; border-radius: 14px; }
  .badge { background: var(--danger-soft); color: var(--danger); font-size: 11px; font-weight: 600; padding: 9px 6px; border-radius: 8px; }
  .device { width: 240px; padding: 16px; margin-top: 20px; }
  .device .btn { width: 100%; justify-content: center; margin-top: 16px; }

  .strip { display: flex; justify-content: space-between; align-items: center; gap: 16px; flex-wrap: wrap; border-top: 1px solid var(--border); padding-top: 28px; padding-bottom: 28px; }
  .strip b { display: inline-flex; align-items: center; gap: 8px; font-size: 15px; font-weight: 600; }
  .strip .icon { font-size: 20px; color: var(--accent); }

  .eyebrow { color: var(--accent); font-size: 12px; font-weight: 600; letter-spacing: 1.2px; text-transform: uppercase; margin-bottom: 12px; }
  .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; margin-top: 40px; }
  .box { padding: 28px; }
  .box p { color: var(--text-2); font-size: 14px; }
  .num { font: 800 36px 'Inter Tight'; color: var(--accent); }
  .split { display: flex; justify-content: space-between; align-items: end; gap: 40px; }
  .split > p { max-width: 380px; color: var(--text-2); }

  .browser-band {
    display: grid; grid-template-columns: 1fr 1.1fr; gap: 48px; align-items: center;
    background: var(--accent-soft); border-radius: 32px; padding: 56px;
  }
  .browser-band h2 { font-size: clamp(30px, 3.4vw, 40px); margin-bottom: 20px; }
  .browser-band p:not(.eyebrow) { color: var(--text-2); margin-bottom: 28px; }
  .window { background: var(--surface); border-radius: 18px; overflow: hidden; box-shadow: 0 24px 50px -20px #2f4bff40; }
  .chrome { display: flex; align-items: center; gap: 6px; padding: 10px 14px; background: var(--muted); }
  .chrome i { width: 10px; height: 10px; border-radius: 50%; background: var(--border-strong); }
  .chrome span { margin-left: 12px; font: 12px 'IBM Plex Mono', monospace; color: var(--text-2); background: var(--surface); padding: 3px 12px; border-radius: 6px; }
  .window .desktop { width: auto; min-width: 1100px; }

  .get { background: var(--dark); color: #fff; text-align: center; padding: 96px 0; }
  .get > .wrap > p { color: #fff9; margin-top: 12px; }
  .dl {
    display: flex; justify-content: space-between; align-items: center; gap: 12px; text-align: left;
    padding: 20px 24px; border-radius: 18px; background: #ffffff0d; border: 1px solid #ffffff1a;
  }
  .dl small { color: #fff9; }
  .dl .row { gap: 8px; flex-wrap: nowrap; }
  .dl.off b { color: #fffa; }

  #faq { align-items: start; padding-top: 96px; padding-bottom: 96px; }
  dl { margin: 0; flex: 0 1 720px; }
  dt { font-weight: 600; padding-top: 24px; border-top: 1px solid var(--border); }
  dd { margin: 8px 0 24px; color: var(--text-2); font-size: 15px; }

  footer { display: flex; justify-content: space-between; align-items: center; gap: 16px; flex-wrap: wrap; padding-top: 32px; padding-bottom: 48px; border-top: 1px solid var(--border); }
  footer a { text-decoration: underline; }

  .btn {
    transition: translate 160ms var(--ease-out), transform 160ms var(--ease-out);
  }
  .btn:not([aria-disabled='true']):active { transform: scale(0.97); }

  @media (hover: hover) and (pointer: fine) {
    .btn:not([aria-disabled='true']):hover { translate: 0 -2px; }
    .nav nav a:not(.btn) { transition: color 160ms ease; }
    .nav nav a:not(.btn):hover { color: var(--accent); }
  }

  @media (prefers-reduced-motion: no-preference) {
    .hero > div:first-child > * { animation: rise 0.7s cubic-bezier(0.2, 0.7, 0.2, 1) both; }
    .hero > div:first-child > :nth-child(2) { animation-delay: 0.06s; }
    .hero > div:first-child > :nth-child(3) { animation-delay: 0.12s; }
    .hero > div:first-child > :nth-child(4) { animation-delay: 0.18s; }
    .hero > div:first-child > :nth-child(5) { animation-delay: 0.24s; }
    .phone { animation: rise 0.9s 0.2s cubic-bezier(0.2, 0.7, 0.2, 1) both; }
    /* Devices turn up one by one, as if just found. */
    .list .tile-row { animation: rise 240ms var(--ease-out) both; }
    .list .tile-row:nth-child(1) { animation-delay: 0ms; }
    .list .tile-row:nth-child(2) { animation-delay: 60ms; }
    .list .tile-row:nth-child(3) { animation-delay: 120ms; }
    .banner { animation: rise 0.6s 2.2s both; }
    .strip > * { animation: rise 0.6s both; }
    .strip > :nth-child(2) { animation-delay: 0.4s; }
    .strip > :nth-child(3) { animation-delay: 0.48s; }
    .strip > :nth-child(4) { animation-delay: 0.56s; }
    .strip > :nth-child(5) { animation-delay: 0.64s; }
    .strip > :nth-child(6) { animation-delay: 0.72s; }
    .toast { animation: rise 0.7s 2.5s both; }
    .dot.blue::before { animation: none; }

    /* Sections rise in as they scroll into view, where browsers support it. */
    @supports (animation-timeline: view()) {
      .box, .browser-band, .dl, dt, dd, #how > h2, #features .split > h2 {
        animation: rise linear both;
        animation-timeline: view();
        animation-range: entry 0% entry 70%;
      }
    }
  }
  @keyframes rise { from { opacity: 0; transform: translateY(16px); } }
  @keyframes pulse { from { box-shadow: 0 0 0 0 #2f4bff66; } to { box-shadow: 0 0 0 8px #2f4bff00; } }

  @media (max-width: 900px) {
    .nav nav a:not(.btn) { display: none; }
    .hero, .browser-band { grid-template-columns: 1fr; }
    .browser-band { padding: 32px 20px; }
    .grid { grid-template-columns: 1fr; }
    .strip { display: grid; grid-template-columns: 1fr 1fr; }
    .strip .fine { grid-column: 1 / -1; }
    .split { flex-direction: column; align-items: start; }
    .stage { min-height: 0; padding-bottom: 110px; }
    .stage::before { width: 360px; height: 360px; right: auto; }
    .stage { justify-content: center; }
    .toast { right: 0; bottom: 0; width: 270px; }
    .window .app { zoom: 0.3 !important; }
  }

  /* Quiet editorial system: reference-led spacing, with Wisp's own identity. */
  :global(:root) {
    --bg: #f6f5f1;
    --surface: #fffefa;
    --muted: #efeee9;
    --border: #e5e2da;
    --border-strong: #cbc7bd;
    --text: #171d2b;
    --text-2: #686c75;
    --accent: #3157d5;
    --accent-soft: #e9edfa;
    --dark: #171d2b;
  }
  :global(body) { background: var(--bg); }
  section { padding-top: 76px; padding-bottom: 76px; }
  .nav { padding-top: 24px; padding-bottom: 24px; }
  .nav nav { gap: 32px; }
  .nav nav a:not(.btn) { color: #50545d; font-weight: 400; }
  .btn { border-radius: 12px; }
  .btn.dark { background: var(--text); }
  .btn.outline { background: transparent; }
  .hero { grid-template-columns: 1.08fr 0.92fr; gap: 56px; padding-top: 34px; padding-bottom: 32px; }
  .hero h1 { max-width: 660px; font-size: clamp(48px, 5.7vw, 70px); line-height: 1.02; }
  .pill { background: transparent; border: 1px solid var(--border); color: #58627b; padding: 7px 12px; margin-bottom: 24px; }
  .pill::before { color: var(--accent); }
  .lead { max-width: 490px; font-size: 18px; line-height: 1.65; margin: 22px 0 28px; }
  .stage { min-height: 620px; justify-content: center; padding: 26px 18px; }
  .stage::before { width: 100%; height: 100%; inset: 0; border-radius: 34px; background: #eeede7; }
  .phone { --z: 0.68; border: 7px solid #222733; border-radius: 42px; box-shadow: 0 28px 65px -38px #17213d99; }
  .toast { right: -12px; bottom: 28px; border-radius: 16px; box-shadow: 0 16px 36px -28px #17213d99; }
  .phone .label .dot.blue { position: relative; }
  .phone .label .dot.blue::before { animation: none; }
  .phone .label .dot.blue::after {
    content: ''; position: absolute; left: 0; top: 50%; width: 8px; height: 8px;
    border: 1px solid var(--accent); border-radius: 50%; pointer-events: none;
    transform: translateY(-50%) scale(.7); opacity: 0;
  }
  .strip { border-color: var(--border); padding-top: 24px; padding-bottom: 24px; }
  .strip b { color: #444956; font-size: 14px; }
  .eyebrow { letter-spacing: 1px; }
  .box { border-radius: 18px; background: var(--surface); box-shadow: none; }
  .grid { gap: 14px; }
  .box h3 { margin-top: 16px; }
  .browser-band { background: #eceef5; border-radius: 28px; padding: 48px; }
  .window { box-shadow: 0 20px 50px -38px #17213d99; }
  .get { padding: 88px 0; }
  .dl { border-radius: 14px; }
  dt { padding-top: 26px; }
  :global(a:focus-visible), :global(button:focus-visible) { outline: 3px solid #3157d5; outline-offset: 4px; }
  @media (prefers-reduced-motion: reduce) {
    :global(*), :global(*::before), :global(*::after) {
      scroll-behavior: auto !important;
      animation: none !important;
      transition: none !important;
    }
  }
  @media (prefers-reduced-motion: no-preference) {
    .stage::before { animation: stage-reveal 900ms 80ms var(--ease-out) both; }
    .phone { animation: phone-arrive 900ms 140ms var(--ease-out) both; }
    .toast { animation: toast-arrive 560ms 700ms var(--ease-out) both; }
    .phone .label .dot.blue::after { animation: signal-wave 1900ms 900ms ease-out infinite; }
    .list .tile-row:nth-child(2) { animation-delay: 70ms; }
    .list .tile-row:nth-child(3) { animation-delay: 140ms; }
    .banner { animation-delay: 1.25s; }
    @media (hover: hover) and (pointer: fine) {
      .box { transition: translate 220ms var(--ease-out), border-color 220ms ease; }
      .box:hover { translate: 0 -3px; border-color: var(--border-strong); }
    }
  }
  @keyframes stage-reveal { from { opacity: 0; transform: scale(.985); } to { opacity: 1; transform: scale(1); } }
  @keyframes phone-arrive { from { opacity: 0; transform: translate3d(0, 22px, 0) scale(.975); } to { opacity: 1; transform: translate3d(0, 0, 0) scale(1); } }
  @keyframes toast-arrive { from { opacity: 0; transform: translate3d(0, 14px, 0) scale(.98); } to { opacity: 1; transform: translate3d(0, 0, 0) scale(1); } }
  @keyframes signal-wave { 0% { transform: translateY(-50%) scale(.7); opacity: .65; } 100% { transform: translateY(-50%) scale(2.8); opacity: 0; } }
  @media (max-width: 900px) {
    section { padding-top: 54px; padding-bottom: 54px; }
    .hero { grid-template-columns: 1fr; gap: 24px; padding-top: 32px; }
    .hero h1 { font-size: clamp(44px, 11vw, 60px); }
    .stage { min-height: 570px; padding: 18px 12px 36px; }
    .stage::before { width: 100%; height: 94%; top: 0; left: 0; }
    .phone { --z: 0.62; }
    .toast { right: -2px; bottom: 0; }
    .grid { grid-template-columns: 1fr; }
    .browser-band { padding: 30px 22px; }
    .get { padding: 64px 0; }
  }
  @media (max-width: 420px) {
    .wrap { padding-left: 18px; padding-right: 18px; }
    .hero .row { align-items: stretch; flex-direction: column; }
    .hero .btn { justify-content: center; }
    .stage { min-height: 510px; }
    .phone { --z: 0.54; }
    .toast { width: 250px; padding: 12px; }
  }
</style>
