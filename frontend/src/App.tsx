import { useEffect, useState } from "react";

export default function App() {
  const [health, setHealth] = useState("checking…");

  useEffect(() => {
    fetch("/api/health")
      .then((res) => res.json())
      .then((body: { status: string }) => setHealth(body.status))
      .catch(() => setHealth("unreachable"));
  }, []);

  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-4 bg-slate-950 text-slate-100">
      <h1 className="text-4xl font-bold">NBA Sim</h1>
      <p className="text-slate-400">
        Backend: <span className="font-mono">{health}</span>
      </p>
    </main>
  );
}
