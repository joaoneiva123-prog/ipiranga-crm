// Avisa o corretor no WhatsApp quando um lead chega para ele:
//   • lead novo (INSERT)                → "LEAD NOVO – ACABOU DE CHEGAR"
//   • lead repassado/transferido (UPDATE com troca de corretor) → "LEAD REPASSADO PARA VOCÊ"
// Disparada por um Database Webhook do Supabase na tabela "leads" (eventos Insert e Update).
//
// Funciona com UM destes dois envios (configure os segredos em Supabase → Edge Functions → Secrets):
//   A) Z-API (número comum conectado por QR Code, mensagem livre com o link do lead)
//        ZAPI_INSTANCE, ZAPI_TOKEN, ZAPI_CLIENT_TOKEN
//   B) API oficial da Meta (WhatsApp Cloud API, modelo aprovado)
//        WHATSAPP_TOKEN, WHATSAPP_PHONE_ID, WHATSAPP_TEMPLATE (padrão: novo_lead)
// Se os segredos da Z-API existirem, ela é usada; senão, a API oficial.
// SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY já existem automaticamente nas Edge Functions.
import { createClient } from "jsr:@supabase/supabase-js@2";

const CRM = "https://ipirangaimobiliaria.com.br/crm/";
const soDig = (t: string) => (t || "").replace(/\D/g, "");
const e164 = (t: string) => { const d = soDig(t); return d.length <= 11 ? "55" + d : d; };
const telBR = (t: string) => { const d = soDig(t).replace(/^55(?=\d{10,11}$)/, ""); return d.length >= 10 ? `+55 (${d.slice(0, 2)}) ${d.slice(2, -4)}-${d.slice(-4)}` : t; };
const hora = () => new Date().toLocaleTimeString("pt-BR", { timeZone: "America/Sao_Paulo", hour: "2-digit", minute: "2-digit" });

Deno.serve(async (req) => {
  try {
    const body = await req.json();
    const lead = body.record, antes = body.old_record;
    if (!lead?.corretor_id) return new Response("sem corretor");
    let repassado = false;
    if (body.type === "INSERT") {
      if (lead.origem_id || lead.etapa !== "novo") return new Response("importado/já em andamento");
    } else if (body.type === "UPDATE") {
      if (!antes || antes.corretor_id === lead.corretor_id) return new Response("sem troca de corretor");
      repassado = true;
    } else return new Response("ignorado");

    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: cor } = await sb.from("profiles").select("nome, whatsapp").eq("id", lead.corretor_id).single();
    if (!cor?.whatsapp) return new Response("corretor sem whatsapp");
    let origem = lead.origem || "Cadastro no CRM";
    if (lead.campanha_id) {
      const { data: c } = await sb.from("campanhas").select("nome").eq("id", lead.campanha_id).single();
      if (c?.nome) origem = c.nome;
    }
    let anterior = "";
    if (repassado && antes?.corretor_id) {
      const { data: a } = await sb.from("profiles").select("nome").eq("id", antes.corretor_id).single();
      anterior = (a?.nome || "").split(" ")[0];
    }
    const primeiro = (cor.nome || "").split(" ")[0];
    const regra = lead.campanha_id || lead.origem === "Site";

    // ---------- A) Z-API: mensagem livre (o 1º link gera a prévia com a logo da Ipiranga)
    const zi = Deno.env.get("ZAPI_INSTANCE"), zt = Deno.env.get("ZAPI_TOKEN");
    if (zi && zt) {
      const msg = [
        `${CRM}?lead=${lead.id}`, "",
        repassado ? "🔄 *LEAD REPASSADO PARA VOCÊ*" : "🔔 *LEAD NOVO – ACABOU DE CHEGAR*",
        `_Ipiranga Gestão Imobiliária · ${hora()}_`, "",
        `👤 *${lead.nome}*`,
        lead.tel ? `📱 ${telBR(lead.tel)}` : "",
        lead.busca ? `🔎 ${lead.busca}` : "",
        `📣 Origem: ${origem}`,
        repassado && anterior ? `↪️ ${anterior} não atendeu a tempo` : "",
        "",
        regra ? "⏱️ Você tem *15 minutos* para o primeiro contato (seg a sex, 8h às 19h). Mova o lead para outra etapa ao atender." : "",
        "👆 Toque no link acima para abrir o lead.",
      ].filter((l, i, a) => l !== "" || (a[i - 1] ?? "") !== "").join("\n");
      const r = await fetch(`https://api.z-api.io/instances/${zi}/token/${zt}/send-text`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "Client-Token": Deno.env.get("ZAPI_CLIENT_TOKEN") || "" },
        body: JSON.stringify({ phone: e164(cor.whatsapp), message: msg }),
      });
      const txt = await r.text();
      return new Response(txt, { status: r.ok ? 200 : 502 });
    }

    // ---------- B) API oficial da Meta: modelo aprovado com 4 variáveis
    const p = (t: string) => ({ type: "text", text: (t || "-").slice(0, 200) });
    const r = await fetch(`https://graph.facebook.com/v21.0/${Deno.env.get("WHATSAPP_PHONE_ID")}/messages`, {
      method: "POST",
      headers: { Authorization: `Bearer ${Deno.env.get("WHATSAPP_TOKEN")}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        messaging_product: "whatsapp",
        to: e164(cor.whatsapp),
        type: "template",
        template: {
          name: Deno.env.get("WHATSAPP_TEMPLATE") || "novo_lead",
          language: { code: "pt_BR" },
          components: [{ type: "body", parameters: [
            p(primeiro),
            p(lead.nome),
            p(lead.tel ? telBR(lead.tel) : "sem telefone"),
            p(repassado ? `${origem} (repassado${anterior ? " de " + anterior : ""})` : origem),
          ] }],
        },
      }),
    });
    const txt = await r.text();
    return new Response(txt, { status: r.ok ? 200 : 502 });
  } catch (e) {
    return new Response(String(e), { status: 500 });
  }
});
