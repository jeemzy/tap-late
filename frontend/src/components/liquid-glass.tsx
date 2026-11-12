import {
  createContext,
  createElement,
  useContext,
  useEffect,
  useRef,
  useState,
  type HTMLAttributes,
  type ReactNode,
  type RefObject,
} from "react";
import { GlassRenderer } from "../lib/glass-renderer";
import { glassScale } from "../lib/glass-settings";
import { useAppearance } from "./appearance-provider";

type Scene = {
  source: HTMLCanvasElement;
  luminance: ImageData;
  target: HTMLElement;
  background: [number, number, number];
};
const GlassScene = createContext<Scene | null>(null);

/** Capture the content plane only when it changes. Scrolling reuses this texture. */
export function GlassSceneProvider({
  target,
  revision,
  background,
  children,
}: {
  target: RefObject<HTMLElement | null>;
  revision: string;
  background: string;
  children: ReactNode;
}) {
  const [scene, setScene] = useState<Scene | null>(null);
  const {
    values: { resolution },
  } = useAppearance();
  useEffect(() => {
    const element = target.current;
    if (!element) return;
    let disposed = false,
      capturing = false,
      pending = false;
    let timer: ReturnType<typeof setTimeout>;
    const color = background.replace("#", "");
    const rgb = [0, 2, 4].map(
      (i) => parseInt(color.slice(i, i + 2), 16) / 255,
    ) as Scene["background"];
    const capture = async () => {
      if (capturing) {
        pending = true;
        return;
      }
      capturing = true;
      try {
        const { default: html2canvas } = await import("html2canvas");
        await Promise.all(
          [...element.querySelectorAll("img")].map((image) =>
            image.decode().catch(() => {}),
          ),
        );
        if (disposed) return;
        const bounds = element.getBoundingClientRect();
        if (!bounds.width || !bounds.height) return;
        const bitmap = await html2canvas(element, {
          backgroundColor: background,
          logging: false,
          imageTimeout: 5000,
          scale: Math.min(
            glassScale(resolution),
            8192 / Math.max(bounds.width, bounds.height),
            Math.sqrt(16_000_000 / (bounds.width * bounds.height)),
          ),
          ignoreElements: (node) => node.hasAttribute("data-glass-decoration"),
          onclone: (document) => {
            const style = document.createElement("style");
            style.textContent =
              "*,*::before,*::after{animation:none!important;transition:none!important;}";
            document.head.append(style);
          },
        });
        // Keep a tiny CPU-side light map; never read back the full texture on scroll.
        const lightMap = document.createElement("canvas");
        lightMap.width = 48;
        lightMap.height = 128;
        const lightContext = lightMap.getContext("2d", {
          willReadFrequently: true,
        });
        if (!lightContext) throw new Error("Canvas is unavailable");
        lightContext.drawImage(bitmap, 0, 0, 48, 128);
        const luminance = lightContext.getImageData(0, 0, 48, 128);
        if (!disposed)
          setScene({
            source: bitmap,
            luminance,
            target: element,
            background: rgb,
          });
      } catch {
        // A blocked image or unsupported canvas keeps the readable CSS material.
        if (!disposed) setScene(null);
      } finally {
        capturing = false;
        if (pending && !disposed) {
          pending = false;
          schedule();
        }
      }
    };
    const schedule = () => {
      clearTimeout(timer);
      timer = setTimeout(() => void capture(), 100);
    };
    schedule();
    const observer = new ResizeObserver(schedule);
    observer.observe(element);
    document.fonts.ready.then(() => {
      if (!disposed) schedule();
    });
    return () => {
      disposed = true;
      clearTimeout(timer);
      observer.disconnect();
    };
  }, [target, revision, background, resolution]);
  return <GlassScene.Provider value={scene}>{children}</GlassScene.Provider>;
}

type Props = HTMLAttributes<HTMLElement> & {
  as?: "header" | "section" | "div";
  elementRef?: RefObject<HTMLElement | null>;
  children: ReactNode;
};

/** Semantic HTML stays interactive above a pointer-transparent optical layer. */
export function LiquidGlass({
  as = "div",
  elementRef,
  className = "",
  children,
  ...props
}: Props) {
  const host = useRef<HTMLElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const scene = useContext(GlassScene);
  const [mode, setMode] = useState("fallback");
  const { values } = useAppearance();
  const appearance = useRef(values);
  const redraw = useRef<() => void>(() => {});
  useEffect(() => {
    appearance.current = values;
    host.current?.style.setProperty("--glass-gloss", String(values.gloss));
    redraw.current();
  }, [values]);
  useEffect(() => {
    const element = host.current,
      surface = canvas.current;
    if (!element || !surface || !scene) return;
    const motion = matchMedia("(prefers-reduced-motion: reduce)");
    const transparency = matchMedia("(prefers-reduced-transparency: reduce)");
    const contrast = matchMedia("(prefers-contrast: more)");
    let renderer: GlassRenderer | null = null;
    let frame = 0,
      disposed = false,
      previous = 0,
      energy = 0,
      velocity = 0,
      pressed = false;
    let pointer: [number, number] = [0.5, 0.2];
    let lastTone = false,
      lastToneTime = -Infinity;
    const start = performance.now();
    const opaque = () => transparency.matches || contrast.matches;
    const tone = (bounds: DOMRect, source: DOMRect, now: number) => {
      if (now - lastToneTime < 120) return lastTone;
      lastToneTime = now;
      let luma =
        scene.background[0] * 0.2126 +
        scene.background[1] * 0.7152 +
        scene.background[2] * 0.0722;
      if (source.width && source.height) {
        let sum = 0,
          count = 0;
        for (const x of [0.2, 0.5, 0.8])
          for (const y of [0.2, 0.7]) {
            const u =
              (bounds.left + bounds.width * x - source.left) / source.width;
            const v =
              (bounds.top + bounds.height * y - source.top) / source.height;
            if (u >= 0 && u < 1 && v >= 0 && v < 1) {
              const index =
                (Math.floor(v * scene.luminance.height) *
                  scene.luminance.width +
                  Math.floor(u * scene.luminance.width)) *
                4;
              const pixel = scene.luminance.data;
              sum +=
                (pixel[index] * 0.2126 +
                  pixel[index + 1] * 0.7152 +
                  pixel[index + 2] * 0.0722) /
                255;
              count++;
            }
          }
        if (count) luma = sum / count;
      }
      // Only the foreground changes for legibility; the optical material has no tone switch.
      lastTone = luma < (lastTone ? 0.55 : 0.4);
      element.dataset.tone = lastTone ? "dark" : "light";
      return lastTone;
    };
    const draw = (now: number) => {
      frame = 0;
      if (disposed || !renderer || document.hidden) return;
      if (opaque()) {
        setMode("opaque");
        return;
      }
      const dt = Math.min((now - (previous || now)) / 1000, 0.032);
      previous = now;
      const target = pressed && !motion.matches ? 1 : 0;
      velocity += ((target - energy) * 190 - velocity * 25) * dt;
      energy += velocity * dt;
      if (motion.matches) {
        energy = 0;
        velocity = 0;
      }
      const bounds = element.getBoundingClientRect();
      const content = scene.target.getBoundingClientRect();
      tone(bounds, content, now);
      element.style.setProperty(
        "--glass-energy",
        String(Math.max(0, energy * appearance.current.press_response)),
      );
      element.style.setProperty("--glass-pointer-x", `${pointer[0] * 100}%`);
      element.style.setProperty("--glass-pointer-y", `${pointer[1] * 100}%`);
      try {
        const rendered = renderer.draw({
          bounds: {
            x: bounds.x,
            y: bounds.y,
            width: bounds.width,
            height: bounds.height,
          },
          scene: {
            x: content.x,
            y: content.y,
            width: content.width,
            height: content.height,
          },
          radius:
            parseFloat(getComputedStyle(element).borderTopLeftRadius) || 28,
          dpr: glassScale(appearance.current.resolution),
          pointer,
          energy: energy * appearance.current.press_response,
          appearance: appearance.current,
          background: scene.background,
          reducedMotion: motion.matches,
        });
        setMode(rendered ? "webgl" : "fallback");
      } catch {
        setMode("fallback");
        renderer.dispose();
        renderer = null;
      }
      if (
        renderer &&
        (Math.abs(energy - target) > 0.002 ||
          Math.abs(velocity) > 0.01 ||
          (!motion.matches && now - start < 450))
      )
        schedule();
    };
    const schedule = () => {
      if (!disposed && !frame) frame = requestAnimationFrame(draw);
    };
    redraw.current = schedule;
    try {
      renderer = new GlassRenderer(surface);
      renderer.setSource(scene.source);
      schedule();
    } catch {
      setMode("fallback");
    }
    const position = (event: PointerEvent) => {
      const bounds = element.getBoundingClientRect();
      pointer = [
        Math.max(0, Math.min(1, (event.clientX - bounds.x) / bounds.width)),
        Math.max(0, Math.min(1, (event.clientY - bounds.y) / bounds.height)),
      ];
      schedule();
    };
    const down = (event: PointerEvent) => {
      pressed = true;
      position(event);
    };
    const up = () => {
      pressed = false;
      schedule();
    };
    const preference = () => {
      if (opaque()) setMode("opaque");
      else schedule();
    };
    const viewport = window.visualViewport;
    const observer = new ResizeObserver(schedule);
    observer.observe(element);
    element.addEventListener("pointermove", position, { passive: true });
    element.addEventListener("pointerdown", down, { passive: true });
    window.addEventListener("pointerup", up, { passive: true });
    window.addEventListener("pointercancel", up, { passive: true });
    window.addEventListener("scroll", schedule, {
      passive: true,
      capture: true,
    });
    window.addEventListener("resize", schedule, { passive: true });
    document.addEventListener("visibilitychange", schedule);
    const lost = () => setMode("fallback");
    surface.addEventListener("webglcontextlost", lost);
    surface.addEventListener("webglcontextrestored", schedule);
    viewport?.addEventListener("resize", schedule);
    viewport?.addEventListener("scroll", schedule);
    motion.addEventListener("change", preference);
    transparency.addEventListener("change", preference);
    contrast.addEventListener("change", preference);
    return () => {
      disposed = true;
      redraw.current = () => {};
      cancelAnimationFrame(frame);
      observer.disconnect();
      renderer?.dispose();
      element.removeEventListener("pointermove", position);
      element.removeEventListener("pointerdown", down);
      window.removeEventListener("pointerup", up);
      window.removeEventListener("pointercancel", up);
      window.removeEventListener("scroll", schedule, true);
      window.removeEventListener("resize", schedule);
      document.removeEventListener("visibilitychange", schedule);
      surface.removeEventListener("webglcontextlost", lost);
      surface.removeEventListener("webglcontextrestored", schedule);
      viewport?.removeEventListener("resize", schedule);
      viewport?.removeEventListener("scroll", schedule);
      motion.removeEventListener("change", preference);
      transparency.removeEventListener("change", preference);
      contrast.removeEventListener("change", preference);
    };
  }, [scene]);
  return createElement(
    as,
    {
      ...props,
      className: `liquid-glass ${className}`,
      "data-optics": mode,
      "data-tone": "light",
      ref: (node: HTMLElement | null) => {
        host.current = node;
        if (elementRef) elementRef.current = node;
      },
    },
    <canvas
      className="glass-optics"
      ref={canvas}
      aria-hidden="true"
      data-glass-decoration=""
    />,
    <span
      className="glass-sheen"
      aria-hidden="true"
      data-glass-decoration=""
    />,
    children,
  );
}
