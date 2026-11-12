import { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import {
  ArrowLeft,
  ArrowUpRight,
  Check,
  Loader2,
  Pause,
  Play,
  RotateCcw,
  ScanLine,
} from "lucide-react";
import { Button } from "./components/ui/button";
import { useAppearance } from "./components/appearance-provider";
import { GlassSceneProvider, LiquidGlass } from "./components/liquid-glass";
import { DEFAULT_GLASS, type GlassSettings } from "./lib/glass-settings";
import "./settings.css";

type Knob = {
  key: Exclude<keyof GlassSettings, "resolution">;
  label: string;
  description: string;
  min: number;
  max: number;
  step: number;
  unit?: "px" | "percent" | "zoom";
  decimals?: number;
};
const groups: { title: string; knobs: Knob[] }[] = [
  {
    title: "Surface",
    knobs: [
      {
        key: "frost",
        label: "Frost",
        description: "A trace of softness, or a more diffused surface.",
        min: 0,
        max: 6,
        step: 0.1,
        unit: "px",
        decimals: 1,
      },
      {
        key: "gloss",
        label: "Glossiness",
        description: "How brightly light catches the polished edges.",
        min: 0,
        max: 2,
        step: 0.05,
        unit: "percent",
      },
      {
        key: "reflection",
        label: "Surface reflection",
        description: "Neutral reflected light. Lower keeps the scene clearer.",
        min: 0,
        max: 0.3,
        step: 0.01,
        unit: "percent",
      },
    ],
  },
  {
    title: "Lens",
    knobs: [
      {
        key: "refraction_strength",
        label: "Refraction",
        description: "How far the glass bends the scene beneath it.",
        min: 0,
        max: 3,
        step: 0.05,
        decimals: 2,
      },
      {
        key: "refraction_index",
        label: "Refractive index",
        description:
          "The optical index. At 1.00, the curved surface stops bending light.",
        min: 1,
        max: 2.4,
        step: 0.01,
        decimals: 2,
      },
      {
        key: "edge_width",
        label: "Edge lensing",
        description:
          "The width of the curved bevel. Small controls cap this to fit.",
        min: 4,
        max: 48,
        step: 1,
        unit: "px",
      },
      {
        key: "curvature",
        label: "Curvature",
        description: "A flatter sheet or a more rounded, outward lens.",
        min: 0,
        max: 4,
        step: 0.1,
        decimals: 1,
      },
      {
        key: "magnification",
        label: "Magnification",
        description: "Enlargement through the center of the lens.",
        min: 1,
        max: 1.15,
        step: 0.005,
        unit: "zoom",
      },
    ],
  },
  {
    title: "Color & touch",
    knobs: [
      {
        key: "dispersion",
        label: "Color separation",
        description: "Red and blue split slightly at the refracting edge.",
        min: 0,
        max: 3,
        step: 0.05,
        unit: "px",
        decimals: 2,
      },
      {
        key: "press_response",
        label: "Press response",
        description: "How much the glass flexes and lights up while held.",
        min: 0,
        max: 2,
        step: 0.05,
        unit: "percent",
      },
    ],
  },
];
const allKnobs = groups.flatMap((group) => group.knobs);
function formatted(knob: Knob, value: number) {
  if (knob.unit === "percent") return `${Math.round(value * 100)}%`;
  if (knob.unit === "zoom") return `${(value * 100).toFixed(1)}%`;
  return `${value.toFixed(knob.decimals ?? 0)}${knob.unit === "px" ? " px" : ""}`;
}

function GlassDemo({ active }: { active: Knob }) {
  const content = useRef<HTMLDivElement>(null),
    scroller = useRef<HTMLDivElement>(null);
  const [theme, setTheme] = useState("color");
  const [playing, setPlaying] = useState(false);
  const [reduced, setReduced] = useState(
    () => matchMedia("(prefers-reduced-motion: reduce)").matches,
  );
  const [tested, setTested] = useState(false);
  useEffect(() => {
    const query = matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => {
      setReduced(query.matches);
      if (query.matches) setPlaying(false);
    };
    query.addEventListener("change", update);
    return () => query.removeEventListener("change", update);
  }, []);
  useEffect(() => {
    if (!playing || reduced) return;
    let frame = 0;
    const start = performance.now();
    const animate = (now: number) => {
      const element = scroller.current;
      if (element)
        element.scrollTop =
          (0.5 - 0.5 * Math.cos((now - start) / 1800)) *
          (element.scrollHeight - element.clientHeight);
      frame = requestAnimationFrame(animate);
    };
    frame = requestAnimationFrame(animate);
    return () => cancelAnimationFrame(frame);
  }, [playing, reduced]);
  return (
    <aside className="appearance-preview" aria-label="Live glass preview">
      <div className="preview-heading">
        <h2>Through the glass</h2>
        <span>Live preview</span>
      </div>
      <div className="demo-themes" aria-label="Preview background">
        {["color", "type", "dark"].map((value) => (
          <button
            key={value}
            type="button"
            aria-pressed={theme === value}
            onClick={() => setTheme(value)}
          >
            {value === "color"
              ? "Color"
              : value === "type"
                ? "Fine detail"
                : "Dark"}
          </button>
        ))}
      </div>
      <GlassSceneProvider
        target={content}
        revision={theme}
        background={theme === "dark" ? "#17171c" : "#f5f5f7"}
      >
        <div className={`demo-frame demo-${theme}`}>
          <div
            className="demo-scroll"
            ref={scroller}
            tabIndex={0}
            aria-label="Scrollable glass test pattern"
            onPointerDown={() => setPlaying(false)}
          >
            <div className="demo-content" ref={content} aria-hidden="true">
              <div className="demo-pattern-heading">
                <ScanLine size={24} />
                <span>Optical test pattern</span>
              </div>
              {Array.from({ length: 8 }, (_, i) => (
                <div className="demo-pattern-row" key={i}>
                  <div className="demo-swatches">
                    <span />
                    <span />
                    <span />
                  </div>
                  <div className="demo-sample-type">
                    <strong>
                      {i % 2
                        ? "Small details. Big difference."
                        : "See the curve, keep the color."}
                    </strong>
                    <span>ABCDEFGHIJKLMNOP · 0123456789</span>
                    <div className="demo-lines" />
                  </div>
                </div>
              ))}
            </div>
          </div>
          <LiquidGlass className="demo-lens">
            <div className="demo-lens-icon">
              <ScanLine size={26} />
            </div>
            <div className="demo-lens-copy">
              <strong>Liquid Glass</strong>
              <span>Scroll the scene beneath it.</span>
            </div>
            <button
              type="button"
              className="demo-press"
              aria-label="Test glass press response"
              onClick={() => setTested(true)}
            >
              <ArrowUpRight size={22} />
            </button>
          </LiquidGlass>
        </div>
      </GlassSceneProvider>
      <div className="demo-play-row">
        <button
          type="button"
          onClick={() => setPlaying(!playing)}
          disabled={reduced}
          aria-pressed={playing}
        >
          {playing ? <Pause size={15} /> : <Play size={15} />}{" "}
          {playing ? "Pause scene" : "Move scene"}
        </button>
        <span>
          {reduced
            ? "Reduced motion is on."
            : "Scroll, hover, or press the glass."}
        </span>
      </div>
      <div className="demo-explanation" aria-live="polite">
        <strong>{active.label}</strong>
        <p>{active.description}</p>
      </div>
      <span className="sr-only" role="status">
        {tested ? "Glass press response demonstrated." : ""}
      </span>
    </aside>
  );
}

export function SettingsPage() {
  const { values, ready, status, error, update, retry } = useAppearance();
  const [active, setActive] = useState(allKnobs[0]);
  return (
    <div className="appearance-page">
      <header className="appearance-header">
        <Link to="/" className="appearance-back">
          <ArrowLeft size={18} />
          <span>Screenshots</span>
        </Link>
        <span className="appearance-brand">
          tap-late<span>.</span>
        </span>
        <span className={`appearance-save save-${status}`} role="status">
          {status === "saving" || status === "loading" ? (
            <Loader2 className="spin" size={15} />
          ) : status === "saved" ? (
            <Check size={15} />
          ) : null}
          {status === "saving"
            ? "Saving…"
            : status === "saved"
              ? "Saved for all devices"
              : status === "loading"
                ? "Connecting…"
                : "Not saved"}
        </span>
      </header>
      <main className="appearance-main">
        <div className="appearance-intro">
          <div>
            <h1>Appearance</h1>
            <p>
              Fine-tune the lens, light, and softness. Changes save
              automatically on this server and sync across your devices.
            </p>
          </div>
          <Button
            variant="ghost"
            disabled={!ready}
            onClick={() => update(DEFAULT_GLASS)}
            aria-label="Reset appearance to default"
          >
            <RotateCcw size={16} /> Reset to default
          </Button>
        </div>
        {error && (
          <div className="appearance-error" role="alert">
            <span>{error}</span>
            <Button variant="ghost" size="sm" onClick={retry}>
              Retry
            </Button>
          </div>
        )}
        <div className="appearance-layout">
          <div className="appearance-controls">
            {groups.map((group) => (
              <section
                className="knob-group"
                key={group.title}
                aria-label={group.title}
              >
                <h2>{group.title}</h2>
                <div className="knob-list">
                  {group.knobs.map((knob) => (
                    <div className="knob" key={knob.key}>
                      <div className="knob-title">
                        <label htmlFor={`glass-${knob.key}`}>
                          {knob.label}
                        </label>
                        <output htmlFor={`glass-${knob.key}`}>
                          {formatted(knob, values[knob.key])}
                        </output>
                      </div>
                      <p id={`help-${knob.key}`}>{knob.description}</p>
                      <input
                        id={`glass-${knob.key}`}
                        type="range"
                        min={knob.min}
                        max={knob.max}
                        step={knob.step}
                        value={values[knob.key]}
                        disabled={!ready}
                        aria-describedby={`help-${knob.key}`}
                        aria-valuetext={formatted(knob, values[knob.key])}
                        onFocus={() => setActive(knob)}
                        onPointerDown={() => setActive(knob)}
                        onChange={(event) => {
                          setActive(knob);
                          update({ [knob.key]: Number(event.target.value) });
                        }}
                      />
                    </div>
                  ))}
                </div>
              </section>
            ))}
            <section className="knob-group">
              <h2>Rendering</h2>
              <fieldset className="quality-control" disabled={!ready}>
                <legend>Glass resolution</legend>
                <div className="quality-options">
                  {(["auto", "2x", "3x"] as const).map((value) => (
                    <label key={value}>
                      <input
                        type="radio"
                        name="resolution"
                        value={value}
                        checked={values.resolution === value}
                        onChange={() => update({ resolution: value })}
                      />
                      <span>
                        {value === "auto"
                          ? "Adaptive"
                          : value === "2x"
                            ? "2×"
                            : "3×"}
                      </span>
                    </label>
                  ))}
                </div>
                <p>
                  Adaptive uses 2× to 3× for your display. 3× sharpens fine
                  edges and uses more graphics memory.
                </p>
              </fieldset>
            </section>
          </div>
          <GlassDemo active={active} />
        </div>
        <p className="appearance-footnote">
          One appearance for this server. Accessibility preferences still apply
          separately on each device.
        </p>
      </main>
    </div>
  );
}
