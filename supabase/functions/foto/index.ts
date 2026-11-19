// Proxy de fotos: busca a foto no site de origem e devolve com permissão (CORS) para o CRM
// colocar a marca d'água e montar o PDF. Só aceita hosts da lista abaixo.
const PERMITIDOS = ["jetimgs.com", "jetimob.com", "supabase.co"];
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
};
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const u = new URL(req.url).searchParams.get("u") || "";
  let alvo: URL;
  try { alvo = new URL(u); } catch { return new Response("url inválida", { status: 400, headers: CORS }); }
  if (alvo.protocol !== "https:" || !PERMITIDOS.some((h) => alvo.hostname === h || alvo.hostname.endsWith("." + h)))
    return new Response("host não permitido", { status: 403, headers: CORS });
  const r = await fetch(alvo.toString());
  if (!r.ok) return new Response("erro " + r.status, { status: 502, headers: CORS });
  const tipo = r.headers.get("content-type") || "image/jpeg";
  if (!tipo.startsWith("image/")) return new Response("não é imagem", { status: 415, headers: CORS });
  return new Response(r.body, { headers: { ...CORS, "Content-Type": tipo, "Cache-Control": "public, max-age=86400" } });
});
