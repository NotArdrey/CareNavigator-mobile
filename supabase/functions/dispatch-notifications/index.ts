import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer@9.0.3";

type OutboxJob = {
  id: number;
  notification_id: string;
  user_id: string;
  channel: "email";
};

type DeliveryResult = { providerId?: string };

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const expectedToken = mustEnv("NOTIFICATION_DISPATCH_TOKEN");
  const suppliedToken = request.headers.get("x-dispatch-token") ?? "";
  if (!constantTimeEqual(expectedToken, suppliedToken)) {
    return json({ error: "Invalid dispatch token" }, 403);
  }

  const admin = createClient(
    mustEnv("SUPABASE_URL"),
    mustEnv("SUPABASE_SERVICE_ROLE_KEY"),
    { auth: { autoRefreshToken: false, persistSession: false } },
  );
  const body = await request.json().catch(() => ({})) as Record<string, unknown>;
  const requested = Number(body.batch_size ?? 50);
  const batchSize = Number.isFinite(requested)
    ? Math.min(100, Math.max(1, Math.trunc(requested)))
    : 50;

  const requestedReminderHours = Number(body.reminder_window_hours ?? 24);
  const reminderWindowHours = Number.isFinite(requestedReminderHours)
    ? Math.min(336, Math.max(1, Math.trunc(requestedReminderHours)))
    : 24;
  let remindersProcessed = 0;
  let reminderProducerError: string | null = null;
  const { data: reminderCount, error: reminderError } = await admin.rpc(
    "enqueue_due_appointment_reminders",
    {
      batch_size: batchSize,
      reminder_window: `${reminderWindowHours} hours`,
    },
  );
  if (reminderError) {
    reminderProducerError = reminderError.message;
    console.error("Could not enqueue appointment reminders", reminderError.message);
  } else {
    remindersProcessed = Number(reminderCount ?? 0);
  }

  const { data, error } = await admin.rpc("claim_notification_outbox", {
    batch_size: batchSize,
  });
  if (error) {
    return json({
      error: `Could not claim notification jobs: ${error.message}`,
      reminders_processed: remindersProcessed,
      reminder_producer_error: reminderProducerError,
    }, 500);
  }

  const jobs = (data ?? []) as OutboxJob[];
  const outcomes: Array<Record<string, unknown>> = [];
  for (const job of jobs) {
    try {
      const context = await loadDeliveryContext(admin, job);
      const result = await deliver(job.channel, context);
      await complete(admin, job.id, true, result.providerId ?? null, null);
      outcomes.push({ id: job.id, channel: job.channel, delivered: true });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Delivery failed";
      await complete(admin, job.id, false, null, message.slice(0, 1000));
      outcomes.push({ id: job.id, channel: job.channel, delivered: false, error: message });
    }
  }

  return json({
    reminders_processed: remindersProcessed,
    reminder_producer_error: reminderProducerError,
    claimed: jobs.length,
    outcomes,
  });
});

async function loadDeliveryContext(
  admin: ReturnType<typeof createClient>,
  job: OutboxJob,
) {
  const [{ data: notification, error: notificationError }, { data: appUser, error: userError }] =
    await Promise.all([
      admin.from("notifications")
        .select("id,title,message,notification_type,action_path,data")
        .eq("id", job.notification_id).single(),
      admin.from("users")
        .select("first_name,last_name,email")
        .eq("auth_user_id", job.user_id).maybeSingle(),
    ]);
  if (notificationError || !notification) throw new Error("Notification no longer exists");
  if (userError) throw new Error(`Could not load recipient: ${userError.message}`);
  return {
    notification,
    user: appUser,
    outboxId: job.id,
  };
}

async function deliver(
  _channel: OutboxJob["channel"],
  context: Awaited<ReturnType<typeof loadDeliveryContext>>,
): Promise<DeliveryResult> {
  return sendEmail(context);
}

async function sendEmail(
  context: Awaited<ReturnType<typeof loadDeliveryContext>>,
): Promise<DeliveryResult> {
  const host = Deno.env.get("SMTP_HOST") ?? "smtp.gmail.com";
  const port = Number(Deno.env.get("SMTP_PORT") ?? "465");
  const username = Deno.env.get("SMTP_USERNAME");
  const password = Deno.env.get("SMTP_PASSWORD");
  const from = Deno.env.get("NOTIFICATION_FROM_EMAIL");
  const email = context.user?.email;
  if (!username || !password || !from) throw new Error("Email provider is not configured");
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error("SMTP_PORT is invalid");
  }
  if (!email) throw new Error("Recipient has no email address");
  const name = [context.user?.first_name, context.user?.last_name]
    .filter((value) => typeof value === "string" && value.trim())
    .join(" ") || "CareNavigator user";
  const appBaseUrl = Deno.env.get("APP_BASE_URL")?.replace(/\/$/, "");
  const actionUrl = appBaseUrl && context.notification.action_path
    ? `${appBaseUrl}/#${context.notification.action_path}`
    : null;
  const actionText = actionUrl ? `\n\nOpen CareNavigator: ${actionUrl}` : "";
  const transport = nodemailer.createTransport({
    host,
    port,
    secure: port === 465,
    auth: { user: username, pass: password },
  });
  const result = await transport.sendMail({
    from,
    to: email,
    subject: context.notification.title,
    messageId: `<carenavigator-notification-${context.outboxId}@carenavigator.local>`,
    text: `Hello ${name},\n\n${context.notification.message}${actionText}\n\nCareNavigator PH`,
    html: `<p>Hello ${escapeHtml(name)},</p><p>${escapeHtml(context.notification.message)}</p>${
      actionUrl
        ? `<p><a href="${escapeHtml(actionUrl)}">Open CareNavigator</a></p>`
        : ""
    }<p>CareNavigator PH</p>`,
  });
  return { providerId: result.messageId };
}

async function complete(
  admin: ReturnType<typeof createClient>,
  id: number,
  delivered: boolean,
  providerId: string | null,
  errorMessage: string | null,
) {
  const { error } = await admin.rpc("complete_notification_delivery", {
    target_outbox_id: id,
    delivered,
    provider_id: providerId,
    error_message: errorMessage,
  });
  if (error) console.error("Could not finalize notification outbox job", id, error.message);
}

function constantTimeEqual(left: string, right: string) {
  const encoder = new TextEncoder();
  const a = encoder.encode(left);
  const b = encoder.encode(right);
  let difference = a.length ^ b.length;
  const length = Math.max(a.length, b.length);
  for (let index = 0; index < length; index++) {
    difference |= (a[index % (a.length || 1)] ?? 0) ^ (b[index % (b.length || 1)] ?? 0);
  }
  return difference === 0;
}

function mustEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not configured`);
  return value;
}

function escapeHtml(value: unknown) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
