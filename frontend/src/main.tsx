import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import {
  BrowserRouter,
  Link,
  Route,
  Routes,
  useNavigate,
  useParams,
} from "react-router-dom";
import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type CSSProperties,
  type DragEvent,
} from "react";
import {
  ArrowDownToLine,
  ArrowLeft,
  ArrowRight,
  Check,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  Copy,
  FileImage,
  Globe2,
  ImagePlus,
  Layers2,
  Loader2,
  ScanLine,
  Settings2,
  Smartphone,
  Trash2,
  Upload,
  X,
} from "lucide-react";
import { Button } from "./components/ui/button";
import {
  ApiError,
  busy,
  request,
  statusText,
  upload,
  type Health,
  type Region,
  type Session,
} from "./api";
import "./styles.css";
import { GlassSceneProvider, LiquidGlass } from "./components/liquid-glass";
import "./liquid-glass.css";

function Brand({ light = false }: { light?: boolean }) {
  return (
    <Link
      to="/"
      className={`brand ${light ? "brand-light" : ""}`}
      aria-label="tap-late home"
    >
      <span className="brand-icon">
        <ScanLine size={22} strokeWidth={1.5} />
      </span>
      tap-late<span className="brand-dot">.</span>
    </Link>
  );
}

function Home() {
  const [sessions, setSessions] = useState<Session[]>([]);
  const [health, setHealth] = useState<Health | null>(null);
  const [error, setError] = useState("");
  const [uploading, setUploading] = useState(false);
  const [dragging, setDragging] = useState(false);
  const [help, setHelp] = useState(false);
  const [deleting, setDeleting] = useState<string | null>(null);
  const input = useRef<HTMLInputElement>(null);
  const content = useRef<HTMLElement>(null);
  const navigate = useNavigate();
  useEffect(() => {
    let active = true;
    const refresh = () =>
      Promise.all([
        request<Session[]>("/api/sessions"),
        request<Health>("/api/health"),
      ])
        .then(([items, config]) => {
          if (active) {
            setSessions(items);
            setHealth(config);
          }
        })
        .catch((e: Error) => {
          if (active) setError(e.message);
        });
    void refresh();
    const timer = setInterval(() => {
      if (!document.hidden) void refresh();
    }, 5000);
    return () => {
      active = false;
      clearInterval(timer);
    };
  }, []);
  async function choose(file?: File) {
    if (!file || uploading) return;
    if (!["image/png", "image/jpeg", "image/webp"].includes(file.type)) {
      setError("Choose a PNG, JPEG, or WebP screenshot.");
      return;
    }
    setError("");
    setUploading(true);
    try {
      const result = await upload(file);
      navigate(result.view_url);
    } catch (e) {
      setError((e as Error).message);
      setUploading(false);
      if (input.current) input.current.value = "";
    }
  }
  async function remove(id: string) {
    setDeleting(id);
    try {
      await request(`/api/sessions/${id}`, { method: "DELETE" });
      setSessions((items) => items.filter((s) => s.id !== id));
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setDeleting(null);
    }
  }
  function drop(event: DragEvent) {
    event.preventDefault();
    setDragging(false);
    void choose(event.dataTransfer.files[0]);
  }
  return (
    <GlassSceneProvider target={content} revision={`${help}:${sessions.map(s => `${s.id}:${s.status}`).join()}`} background="#f5f5f7">
    <div className="home">
      <LiquidGlass as="header" className="home-header">
        <Brand />
        <span className="private-badge">
          <span />
          Your private workspace
        </span>
        <Button
          variant="ghost"
          size="sm"
          onClick={() => setHelp(!help)}
          aria-expanded={help}
        >
          <Smartphone size={17} /> iPhone setup
        </Button>
      </LiquidGlass>
      <main className="home-main" ref={content}>
        <section className="upload-section" aria-labelledby="upload-title">
          <div className="intro">
            <div className="language-pair">
              <span>中</span>
              <ArrowRight size={16} />
              <span>En</span>
            </div>
            <h1 id="upload-title">
              A little less lost
              <br />
              in translation.
            </h1>
            <p>
              Chinese screenshots. English, right where it belongs.
              <br className="desktop-break" /> Drop one in and tap any
              translation to look closer.
            </p>
          </div>
          <div
            className={`drop-zone ${dragging ? "dragging" : ""} ${uploading ? "uploading" : ""}`}
            onDragOver={(e) => {
              e.preventDefault();
              setDragging(true);
            }}
            onDragLeave={() => setDragging(false)}
            onDrop={drop}
          >
            <div className="drop-icon">
              {uploading ? (
                <Loader2 className="spin" size={30} />
              ) : (
                <ImagePlus size={30} strokeWidth={1.4} />
              )}
            </div>
            <h2>
              {uploading
                ? "Sending your screenshot…"
                : "Drop a screenshot here"}
            </h2>
            <p>
              {uploading
                ? "Your viewer will open in a moment."
                : "Or choose one from your photos or files."}
            </p>
            <Button disabled={uploading} onClick={() => input.current?.click()}>
              <Upload size={17} />
              {uploading ? "Uploading…" : "Choose screenshot"}
              <ArrowRight size={17} />
            </Button>
            <input
              ref={input}
              type="file"
              accept="image/png,image/jpeg,image/webp"
              className="sr-only"
              aria-label="Choose screenshot file"
              tabIndex={-1}
              onChange={(e) => void choose(e.target.files?.[0])}
            />
            <span className="file-hint">PNG, JPG or WebP · up to 20 MB</span>
          </div>
          {error && (
            <p className="error-message" role="alert">
              {error}
            </p>
          )}
          {health && !health.translation_configured && (
            <p className="setup-notice">
              <Settings2 size={17} />
              <span>
                One thing to connect: add your OpenAI key to the server’s{" "}
                <code>.env</code> file, then restart.
              </span>
            </p>
          )}
          <div className="workflow-note">
            <ScanLine size={16} />
            <span>Text stays in place.</span>
            <span className="note-separator" />
            <Layers2 size={16} />
            <span>The original is always underneath.</span>
          </div>
        </section>
        <section className="recent-section" aria-labelledby="recent-title">
          <div className="section-heading">
            <div>
              <h2 id="recent-title">
                Recent screenshots <span>{sessions.length}</span>
              </h2>
              <p>
                Yours to revisit. Kept for {health?.retention_days ?? 7} days.
              </p>
            </div>
            <span className="language-tag">
              ZH <ArrowRight size={12} /> EN
            </span>
          </div>
          {sessions.length === 0 ? (
            <div className="empty-history">
              <FileImage size={27} strokeWidth={1.2} />
              <p>A new perspective starts here.</p>
              <span>Your screenshots will appear after you upload one.</span>
            </div>
          ) : (
            <div className="session-list">
              {sessions.map((session, i) => (
                <article className="session-row" key={session.id}>
                  <Link to={session.view_url} className="session-link">
                    <img
                      className="session-thumb"
                      src={session.original_url}
                      alt=""
                      loading="lazy"
                    />
                    <div className="session-meta">
                      <h3>
                        {session.regions.find((r) => r.translation && r.translation !== r.source)
                          ?.translation ||
                          `Screenshot ${new Date(session.created_at * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}`}
                      </h3>
                      <p>
                        {new Date(session.created_at * 1000).toLocaleDateString(
                          [],
                          { month: "short", day: "numeric" },
                        )}
                        <span>·</span>
                        {session.regions.length
                          ? `${session.regions.length} text regions`
                          : "Chinese → English"}
                      </p>
                    </div>
                    <span className={`session-status status-${session.status}`}>
                      {busy(session) && <Loader2 size={12} className="spin" />}
                      {session.status === "ready" ? <Check size={14} /> : null}
                      {statusText[session.status]}
                    </span>
                    <ChevronRight size={17} className="row-chevron" />
                  </Link>
                  <Button
                    variant="ghost"
                    size="icon"
                    className="delete-button"
                    aria-label={`Delete screenshot ${i + 1}`}
                    disabled={deleting === session.id}
                    onClick={() => void remove(session.id)}
                  >
                    {deleting === session.id ? (
                      <Loader2 className="spin" size={17} />
                    ) : (
                      <Trash2 size={17} />
                    )}
                  </Button>
                </article>
              ))}
            </div>
          )}
        </section>
        {help && (
          <section className="shortcut-help">
            <div>
              <h2>One tap from your iPhone.</h2>
              <Button
                variant="ghost"
                size="icon"
                aria-label="Close iPhone setup"
                onClick={() => setHelp(false)}
              >
                <X size={19} />
              </Button>
            </div>
            <p>Connect to your Wi-Fi or WireGuard network. In Shortcuts:</p>
            <ol>
              <li>Take a screenshot and generate a UUID.</li>
              <li>
                POST the image as <code>file</code> and UUID as{" "}
                <code>session_id</code> to{" "}
                <code>{location.origin}/api/sessions</code>.
              </li>
              <li>
                Open this server address followed by the returned{" "}
                <code>view_url</code>.
              </li>
            </ol>
            <p>
              Assign the Shortcut to Back Tap or the Action Button. The
              repository’s Shortcut guide has the complete steps.
            </p>
          </section>
        )}
      </main>
      <footer className="home-footer">
        <span>From screenshot to understanding.</span>
        <span>
          <Globe2 size={14} /> Local OCR · OpenAI translation
        </span>
      </footer>
    </div>
    </GlassSceneProvider>
  );
}

function TranslationRegion({
  region,
  selected,
  translated,
  onSelect,
  scale,
}: {
  region: Region;
  selected: boolean;
  translated: boolean;
  onSelect: (element: HTMLButtonElement) => void;
  scale: number;
}) {
  const element = useRef<HTMLButtonElement>(null);
  const text = useRef<HTMLSpanElement>(null);
  const [overflow, setOverflow] = useState(false);
  useLayoutEffect(() => {
    const fit = () => {
      const box = element.current,
        label = text.current;
      if (!box || !label) return;
      const height = box.clientHeight,
        width = box.clientWidth;
      if (!height || !width) return;
      const max = Math.max(8, Math.min(36 / scale, height * 0.85)),
        min = Math.min(max, 9 / scale);
      let size = max;
      label.style.fontSize = `${size}px`;
      while (
        size > min &&
        (label.scrollHeight > height - 2 || label.scrollWidth > width - 2)
      ) {
        size -= 0.5;
        label.style.fontSize = `${size}px`;
      }
      const clipped =
        label.scrollHeight > height - 2 || label.scrollWidth > width - 2;
      setOverflow(clipped);
    };
    fit();
    const observer = new ResizeObserver(fit);
    if (element.current) observer.observe(element.current);
    return () => observer.disconnect();
  }, [region.translation, translated, scale]);
  const style = {
    left: `${region.box[0]}px`,
    top: `${region.box[1]}px`,
    width: `${region.box[2]}px`,
    height: `${region.box[3]}px`,
    background:
      translated && region.translation ? region.background : "transparent",
    color: region.foreground,
  } as CSSProperties;
  return (
    <button
      ref={element}
      type="button"
      className={`region ${selected ? "selected" : ""} ${translated ? "" : "source-region"}`}
      style={style}
      onClick={(event) => onSelect(event.currentTarget)}
      aria-label={`${region.translation || region.source}. Show original and full translation`}
      aria-pressed={selected}
      title={region.translation || region.source}
    >
      {translated && region.translation && (
        <span
          ref={text}
          className={`region-text ${overflow ? "text-clipped" : ""}`}
        >
          {region.translation}
        </span>
      )}
      {overflow && translated && (
        <span className="overflow-mark" aria-hidden="true">
          …
        </span>
      )}
    </button>
  );
}

function Viewer() {
  const { id } = useParams();
  const [session, setSession] = useState<Session | null>(null);
  const [error, setError] = useState("");
  const [selected, setSelected] = useState<Region | null>(null);
  const [translated, setTranslated] = useState(true);
  const [retrying, setRetrying] = useState(false);
  const [copied, setCopied] = useState(false);
  const [copyError, setCopyError] = useState("");
  const [scale, setScale] = useState(1);
  const stage = useRef<HTMLDivElement>(null);
  const island = useRef<HTMLElement>(null);
  const lastRegion = useRef<HTMLElement | null>(null);
  const pollGeneration = useRef(0);
  const refresh = useCallback(async () => {
    const data = await request<Session>(`/api/sessions/${id}`);
    setSession(data);
    setError("");
    return data;
  }, [id]);
  useEffect(() => {
    const generation = ++pollGeneration.current;
    let timer: ReturnType<typeof setTimeout>;
    const poll = async () => {
      try {
        const data = await request<Session>(`/api/sessions/${id}`);
        if (pollGeneration.current !== generation) return;
        setSession(data);
        setSelected(
          (current) => data.regions.find((r) => r.id === current?.id) || null,
        );
        setError("");
        if (busy(data)) timer = setTimeout(poll, 1200);
      } catch (e) {
        if (pollGeneration.current !== generation) return;
        setError((e as Error).message);
        if (e instanceof ApiError && [400, 404, 410, 422].includes(e.status))
          setSession(null);
        else timer = setTimeout(poll, 3000);
      }
    };
    setSession(null);
    setSelected(null);
    void poll();
    const online = () => {
      clearTimeout(timer);
      void poll();
    };
    window.addEventListener("online", online);
    return () => {
      ++pollGeneration.current;
      clearTimeout(timer);
      window.removeEventListener("online", online);
    };
  }, [id, retrying]);
  useEffect(() => {
    if (!stage.current || !session) return;
    const target = stage.current;
    const resize = () => setScale(target.clientWidth / session.width);
    resize();
    const observer = new ResizeObserver(resize);
    observer.observe(target);
    return () => observer.disconnect();
  }, [session?.width, session?.height]);
  function close() {
    setSelected(null);
    setCopyError("");
    lastRegion.current?.focus({ preventScroll: true });
  }
  useEffect(() => {
    const key = (event: KeyboardEvent) => {
      if (event.key === "Escape") close();
    };
    document.addEventListener("keydown", key);
    return () => document.removeEventListener("keydown", key);
  }, []);
  function select(region: Region, element: HTMLButtonElement) {
    // Touch browsers can leave BODY focused; use the tapped region as the anchor.
    lastRegion.current = element;
    setSelected(region);
    setCopied(false);
    setCopyError("");
    setTimeout(() => {
      const bounds = element.getBoundingClientRect();
      const panel = island.current?.getBoundingClientRect();
      // Measure the final island position while its entrance is still animating.
      const offset = island.current
        ? new DOMMatrixReadOnly(getComputedStyle(island.current).transform).m42
        : 0;
      if (bounds && panel && bounds.bottom > panel.top - offset - 16)
        window.scrollBy({
          top: bounds.bottom - (panel.top - offset) + 24,
          behavior: matchMedia("(prefers-reduced-motion: reduce)").matches
            ? "instant"
            : "smooth",
        });
    }, 30);
  }
  async function retry() {
    setRetrying(true);
    try {
      await request(`/api/sessions/${id}/retry`, { method: "POST" });
      await refresh();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setRetrying(false);
    }
  }
  async function copy() {
    const value = selected?.translation || selected?.source || "";
    try {
      if (navigator.clipboard && window.isSecureContext)
        await navigator.clipboard.writeText(value);
      else {
        const field = document.createElement("textarea");
        field.value = value;
        field.style.position = "fixed";
        field.style.opacity = "0";
        document.body.append(field);
        field.select();
        const ok = document.execCommand("copy");
        field.remove();
        if (!ok) throw new Error("Copy unavailable");
      }
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    } catch {
      setCopyError("Select the text below to copy it manually.");
    }
  }
  if (!session)
    return (
      <div className="viewer-empty">
        <Brand light />
        {error ? (
          <>
            <h1>We couldn’t open that screenshot.</h1>
            <p role="alert">{error}</p>
            <Button asChild>
              <Link to="/">
                Upload a screenshot <ArrowRight size={17} />
              </Link>
            </Button>
          </>
        ) : (
          <p role="status">
            <Loader2 className="spin" size={20} /> Opening your screenshot…
          </p>
        )}
      </div>
    );
  const processing = busy(session);
  return (
    <GlassSceneProvider target={stage} revision={`${session.id}:${session.status}:${translated}:${session.regions.map(r => r.translation).join()}`} background="#161618">
    <main className={`viewer ${selected ? "has-selection" : ""}`}>
      <LiquidGlass as="header" className="viewer-toolbar">
        <Link to="/" className="back-control" aria-label="Back to screenshots">
          <ArrowLeft size={18} />
        </Link>
        <Brand light />
        <span className="toolbar-spacer" />
        <span className="viewer-language">
          ZH <ArrowRight size={13} /> EN
        </span>
        <span className="toolbar-divider" />
        <Button
          variant="ghost"
          size="icon"
          className="glass-button"
          onClick={() => setTranslated((value) => !value)}
          aria-label={
            translated
              ? "Show original screenshot"
              : "Show translated screenshot"
          }
          aria-pressed={!translated}
        >
          <Layers2 size={21} />
        </Button>
      </LiquidGlass>
      <div
        className="viewer-stage"
        ref={stage}
        style={{ aspectRatio: `${session.width}/${session.height}` }}
      >
        <img
          className="original-image"
          src={session.original_url}
          width={session.width}
          height={session.height}
          alt="Your original Chinese screenshot"
          onError={() =>
            setError(
              "The screenshot image is unavailable. Return to recent screenshots and upload it again.",
            )
          }
        />
        <div
          className="region-layer"
          style={
            {
              width: session.width,
              height: session.height,
              transform: `scale(${scale})`,
              "--region-scale": scale,
            } as CSSProperties
          }
        >
          {session.regions.map((region) => (
            <TranslationRegion
              key={region.id}
              region={region}
              selected={selected?.id === region.id}
              translated={translated}
              scale={scale}
              onSelect={(element) => select(region, element)}
            />
          ))}
        </div>
      </div>
      {!selected && (
        <div className="viewer-caption">
          {processing ? (
            <>
              <Loader2 className="spin" size={15} />
              {statusText[session.status]}…
            </>
          ) : session.status === "ready" ? (
            <>
              <ScanLine size={15} />
              {session.regions.length
                ? `${translated ? "Tap any translation" : "Original view · tap text to inspect"}`
                : "No readable text found in this screenshot."}
            </>
          ) : null}
        </div>
      )}
      {(session.status === "failed" || error) && (
        <LiquidGlass as="section" className="processing-error" role="alert">
          <h2>
            {error
              ? "Reconnecting to your screenshot."
              : "Let’s try that again."}
          </h2>
          <p>{error || session.error}</p>
          <Button
            disabled={retrying || (!error && session.status !== "failed")}
            onClick={() => (error ? window.location.reload() : void retry())}
          >
            {retrying ? <Loader2 className="spin" size={16} /> : null}
            {error ? "Reconnect now" : "Retry translation"}
          </Button>
        </LiquidGlass>
      )}
      {selected && (
        <LiquidGlass as="section"
          elementRef={island}
          className="detail-island"
          aria-label="Translation details"
        >
          <div className="island-top">
            <span className="island-selection">
              <span />
              {selected.id}{" "}
              <span className="island-languages">
                Chinese <ArrowRight size={11} /> English
              </span>
            </span>
            <div className="island-actions">
              <Button
                variant="ghost"
                size="icon"
                className="glass-button"
                aria-label="Copy translation"
                onClick={() => void copy()}
              >
                {copied ? <Check size={18} /> : <Copy size={17} />}
              </Button>
              <Button
                variant="ghost"
                size="icon"
                className="glass-button"
                aria-label="Close translation details"
                onClick={close}
              >
                <X size={20} />
              </Button>
            </div>
          </div>
          <div className="island-content" key={selected.id}>
            <div className="detail-source">
              <span>Original</span>
              <p lang="zh">{selected.source}</p>
            </div>
            <div className="detail-translation">
              <span>Translation</span>
              <p>
                {selected.translation ||
                  (processing
                    ? "Translation is on its way…"
                    : "This text could not be translated reliably.")}
              </p>
            </div>
          </div>
          {copyError && (
            <p className="copy-error" role="status">
              {copyError}
            </p>
          )}
        </LiquidGlass>
      )}
      <span className="sr-only" role="status" aria-live="polite">
        {processing
          ? statusText[session.status]
          : session.status === "ready"
            ? `Translation ready. ${session.regions.length} text regions.`
            : session.error}
      </span>
    </main>
    </GlassSceneProvider>
  );
}

function NotFound() {
  return (
    <div className="viewer-empty">
      <Brand light />
      <h1>Nothing at this address.</h1>
      <Button asChild>
        <Link to="/">Back to screenshots</Link>
      </Button>
    </div>
  );
}
createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Home />} />
        <Route path="/view/:id" element={<Viewer />} />
        <Route path="*" element={<NotFound />} />
      </Routes>
    </BrowserRouter>
  </StrictMode>,
);
