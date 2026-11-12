import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { Loader2 } from "lucide-react";
import { request, type Amount, type Conversion, type Currency, type Region } from "../api";
import { Button } from "./ui/button";
import "../currency.css";

const currencies: { code: Currency; name: string; symbol: string }[] = [
  { code: "CNY", name: "Yuan", symbol: "¥" },
  { code: "PLN", name: "Złoty", symbol: "zł" },
  { code: "USD", name: "Dollar", symbol: "$" },
  { code: "EUR", name: "Euro", symbol: "€" },
];

export function CurrencyDetails({ sessionId, region, onSave, onHeading, translationFallback }: {
  sessionId: string;
  region: Region;
  onSave: (amountId: string, currency: Currency) => Promise<Amount>;
  onHeading: (title: string) => void;
  translationFallback: string;
}) {
  const amounts = region.amounts || [];
  const [activeId, setActiveId] = useState(amounts[0]?.id);
  const amount = amounts.find(a => a.id === activeId) || amounts[0];
  return <>
    {amounts.length > 1 && <div className="amount-chips" role="group" aria-label="Choose amount">
      {amounts.map((a, i) => <button key={a.id} type="button" aria-pressed={a.id === amount.id}
        aria-label={`Amount ${i + 1}: ${a.text}`} onClick={() => setActiveId(a.id)}>{a.text}</button>)}
    </div>}
    <AmountDetails key={amount.id} sessionId={sessionId} region={region} amount={amount}
      onSave={onSave} onHeading={onHeading} translationFallback={translationFallback} />
  </>;
}

function AmountDetails({ sessionId, region, amount, onSave, onHeading, translationFallback }: {
  sessionId: string; region: Region; amount: Amount;
  onSave: (amountId: string, currency: Currency) => Promise<Amount>; onHeading: (title: string) => void;
  translationFallback: string;
}) {
  const [picker, setPicker] = useState(false);
  const [draft, setDraft] = useState<Currency | null>(null);
  const [result, setResult] = useState<Conversion | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const generation = useRef(0);
  const root = useRef<HTMLDivElement>(null);
  const action = useRef<HTMLButtonElement>(null);
  const focusAfter = useRef(false);
  const source = amount.source_currency || amount.detected_currency;
  const base = `/api/sessions/${sessionId}/regions/${region.id}/amounts/${amount.id}`;
  const title = picker ? (amount.source_currency ? "Change source currency" : `Currency of ${amount.text}`)
    : result ? "Currency conversion" : amount.detected_currency ? "Price details" : "Amount details";

  useEffect(() => () => { ++generation.current; }, []);
  useLayoutEffect(() => { onHeading(title); }, [title, onHeading]);
  useLayoutEffect(() => {
    if (!focusAfter.current) return;
    focusAfter.current = false;
    // Explicit preventScroll keeps keyboard focus from moving the screenshot.
    const target = picker ? (root.current?.querySelector<HTMLInputElement>("input:checked")
      || root.current?.querySelector<HTMLInputElement>("input")) : action.current;
    target?.focus({ preventScroll: true });
  }, [picker, result]);

  function chooseCurrency() {
    setDraft(source);
    setError("");
    focusAfter.current = true;
    setPicker(true);
  }
  function cancel() {
    focusAfter.current = true;
    setPicker(false);
    setError("");
  }
  useEffect(() => {
    if (!picker) return;
    // WebKit may leave BODY focused after a pointer choice. Escape still cancels
    // the draft before the viewer's document-level close handler can run.
    const escape = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      event.preventDefault();
      event.stopImmediatePropagation();
      if (!pending) cancel();
    };
    document.addEventListener("keydown", escape, true);
    return () => document.removeEventListener("keydown", escape, true);
  }, [picker, pending]);
  async function convert(currency: Currency, save: boolean) {
    if (pending) return;
    const token = ++generation.current;
    setPending(true);
    setError("");
    try {
      if (save) {
        await onSave(amount.id, currency);
        if (token !== generation.current) return;
      }
      if (token !== generation.current) return;
      focusAfter.current = true;
      setPicker(false);
      setResult(null);
      const converted = await request<Conversion>(base + "/convert", { method: "POST" });
      if (token === generation.current) {
        focusAfter.current = true;
        setResult(converted);
      }
    } catch (e) {
      if (token === generation.current) setError((e as Error).message);
    } finally {
      if (token === generation.current) setPending(false);
    }
  }
  function start() {
    if (!source) chooseCurrency();
    else void convert(source, !amount.source_currency);
  }
  return <div ref={root} className="currency-details">
    {picker ? <>
      <p className="currency-prompt">{amount.source_currency
        ? `Current: ${amount.source_currency} · ${currencies.find(c => c.code === amount.source_currency)?.name}`
        : "What currency is this amount?"}</p>
      <fieldset className="currency-picker" disabled={pending}>
        <legend className="sr-only">Source currency for {amount.text}</legend>
        {currencies.map(c => <label key={c.code}>
          <input type="radio" name={`currency-${amount.id}`} value={c.code} checked={draft === c.code}
            onChange={() => setDraft(c.code)} />
          <span>{c.code} · {c.name}</span>
        </label>)}
      </fieldset>
      <Button className="convert-action" disabled={!draft || pending}
        onClick={() => draft && void convert(draft, true)}>
        {pending && <Loader2 size={16} className="spin" />}
        {amount.source_currency ? "Save & update" : "Confirm & convert"}
      </Button>
      <button className="currency-link cancel-currency" disabled={pending} onClick={cancel}>Cancel</button>
    </> : <>
      <dl className="amount-original">
        <div><dt>Original</dt><dd lang="zh">{region.source}</dd></div>
        <div><dt>Translation</dt><dd>{region.translation || translationFallback}</dd></div>
      </dl>
      {result ? <>
        <dl className="conversion-grid" aria-label="Converted amounts">
          {currencies.map(c => <div key={c.code}>
            <dt>{c.code}</dt><dd>{c.symbol}{result.values[c.code]}</dd>
          </div>)}
        </dl>
        <p className="rate-note">Approx. · {result.rate_date}</p>
        <div className="conversion-actions">
          <button ref={action} className="currency-link" onClick={() => {
            focusAfter.current = true; setResult(null); setError("");
          }}>Hide conversion</button>
          <button className="currency-link" onClick={chooseCurrency}>Change currency</button>
        </div>
      </> : <>
        {amount.source_currency && <div className="saved-currency">
          <span>Source: {amount.source_currency} · {currencies.find(c => c.code === amount.source_currency)?.name}</span>
          <button className="currency-link" disabled={pending} onClick={chooseCurrency}>Change currency</button>
        </div>}
        <Button ref={action} className="convert-action" disabled={pending} onClick={start}>
          {pending && <Loader2 className="spin" size={16} />}
          {pending ? "Converting…" : error ? "Retry" : amount.source_currency
            ? `Convert from ${amount.source_currency}` : amount.detected_currency ? "Convert price" : "Convert amount"}
        </Button>
      </>}
    </>}
    {pending && <span className="sr-only" role="status">Loading currency conversion</span>}
    {error && <p className="currency-error" role="alert">{error}</p>}
    {result && <span className="sr-only" role="status">Conversion ready. Approximate rates from {result.rate_date}.</span>}
  </div>;
}
