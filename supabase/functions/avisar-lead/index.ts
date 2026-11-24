// Avisa o corretor no WhatsApp (API oficial da Meta) quando um lead novo é atribuído a ele.
// Disparada por um Database Webhook do Supabase em INSERT na tabela "leads".
// Segredos necessários (Supabase → Edge Functions → Secrets):
//   WHATSAPP_TOKEN     token permanente do usuário do sistema (Meta Business)
//   WHATSAPP_PHONE_ID  "Phone number ID" do número da Ipiranga na API
//   WHATSAPP_TEMPLATE  nome do modelo aprovado (padrão: novo_lead)
// SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY já existem automaticamente nas Edge Functions.
import { createClient } from "jsr:@supabase/supabase-js@2";

const soDig = (t: string) => (t || "").replace(/\D/g, "");
const e164 = (t: string) => { const d = soDig(t); return d.length <= 11 ? "55" + d : d; };

Deno.serve(async (req) => {
  try {
    const body = await req.json();
    const lead = body.record;
    if (body.type !== "INSERT" || !lead?.corretor_id) return new Response("ignorado");
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: cor } = await sb.from("profiles").select("nome, whatsapp").eq("id", lead.corretor_id).single();
    if (!cor?.whatsapp) return new Response("corretor sem whatsapp");
    let campanha = lead.origem || "Cadastro no CRM";
    if (lead.campanha_id) {
      const { data: c } = await sb.from("campanhas").select("nome").eq("id", lead.campanha_id).single();
      if (c?.nome) campanha = c.nome;
    }
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
            p((cor.nome || "").split(" ")[0]),
            p(lead.nome),
            p(lead.tel ? `+${e164(lead.tel)}` : "sem telefone"),
            p(campanha),
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
