import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { request } from "../api";
import { DEFAULT_GLASS, type GlassSettings } from "../lib/glass-settings";

const endpoint = "/api/settings/appearance";
type State = {
  values: GlassSettings;
  ready: boolean;
  status: "loading" | "saved" | "saving" | "error";
  error: string;
  update: (changes: Partial<GlassSettings>) => void;
  retry: () => void;
};
const Appearance = createContext<State>({
  values: DEFAULT_GLASS,
  ready: false,
  status: "loading",
  error: "",
  update: () => {},
  retry: () => {},
});
export const useAppearance = () => useContext(Appearance);

/** The server owns appearance. No local-storage profile can override another device. */
export function AppearanceProvider({ children }: { children: ReactNode }) {
  const [values, setValues] = useState(DEFAULT_GLASS);
  const [ready, setReady] = useState(false);
  const [status, setStatus] = useState<State["status"]>("loading");
  const [error, setError] = useState("");
  const pending = useRef<Partial<GlassSettings>>({});
  const writing = useRef(false);
  const editRevision = useRef(0);
  const mounted = useRef(false);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const flushRef = useRef<() => void>(() => {});
  const loadRef = useRef<() => void>(() => {});
  const flush = useCallback(async () => {
    if (writing.current || !Object.keys(pending.current).length) return;
    const batch = pending.current;
    pending.current = {};
    writing.current = true;
    let succeeded = false;
    try {
      const saved = await request<GlassSettings>(endpoint, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(batch),
        keepalive: true,
      });
      succeeded = true;
      if (mounted.current) {
        setValues({ ...DEFAULT_GLASS, ...saved, ...pending.current });
        setError("");
        setStatus(Object.keys(pending.current).length ? "saving" : "saved");
      }
    } catch {
      pending.current = { ...batch, ...pending.current };
      if (mounted.current) {
        setStatus("error");
        setError(
          "Couldn’t save to the server. Your changes are still shown here.",
        );
      }
    } finally {
      writing.current = false;
      if (succeeded && mounted.current && Object.keys(pending.current).length)
        flushRef.current();
    }
  }, []);
  flushRef.current = () => void flush();
  useEffect(() => {
    mounted.current = true;
    let disposed = false;
    let readSequence = 0;
    const refresh = async () => {
      if (writing.current || Object.keys(pending.current).length) return;
      const sequence = ++readSequence;
      const revision = editRevision.current;
      try {
        const saved = { ...DEFAULT_GLASS, ...await request<GlassSettings>(endpoint) };
        if (
          disposed ||
          sequence !== readSequence ||
          revision !== editRevision.current ||
          writing.current ||
          Object.keys(pending.current).length
        )
          return;
        setValues((current) =>
          JSON.stringify(current) === JSON.stringify(saved) ? current : saved,
        );
        setReady(true);
        setStatus("saved");
        setError("");
      } catch {
        if (
          !disposed &&
          sequence === readSequence &&
          revision === editRevision.current
        ) {
          setStatus("error");
          setError(
            "Couldn’t connect to appearance settings. Check your connection and retry.",
          );
        }
      }
    };
    loadRef.current = () => void refresh();
    void refresh();
    const sync = () => {
      if (!document.hidden) void refresh();
    };
    const interval = setInterval(sync, 3000);
    window.addEventListener("focus", sync);
    document.addEventListener("visibilitychange", sync);
    const leave = () => flushRef.current();
    window.addEventListener("pagehide", leave);
    return () => {
      disposed = true;
      mounted.current = false;
      clearInterval(interval);
      clearTimeout(timer.current);
      window.removeEventListener("focus", sync);
      document.removeEventListener("visibilitychange", sync);
      window.removeEventListener("pagehide", leave);
    };
  }, []);
  const update = useCallback((changes: Partial<GlassSettings>) => {
    editRevision.current++;
    pending.current = { ...pending.current, ...changes };
    setValues((current) => ({ ...current, ...changes }));
    setStatus("saving");
    setError("");
    clearTimeout(timer.current);
    timer.current = setTimeout(() => flushRef.current(), 350);
  }, []);
  const retry = () => {
    if (Object.keys(pending.current).length) {
      setStatus("saving");
      flushRef.current();
    } else {
      setStatus("loading");
      loadRef.current();
    }
  };
  return (
    <Appearance.Provider
      value={{ values, ready, status, error, update, retry }}
    >
      {children}
    </Appearance.Provider>
  );
}
