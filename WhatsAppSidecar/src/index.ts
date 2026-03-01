/**
 * AutoClawd WhatsApp Sidecar
 *
 * Local HTTP server + Baileys WhatsApp Web client.
 * Managed by the Swift app — communicates via REST on localhost.
 *
 * Endpoints:
 *   GET  /health              — connection status
 *   GET  /qr                  — current QR code as base64 PNG
 *   GET  /messages?since=<ts> — poll new messages since Unix timestamp
 *   POST /send                — send message {jid, text}
 *   POST /disconnect          — disconnect + clear auth
 */

import fs from 'fs';
import path from 'path';
import { Readable } from 'stream';

import makeWASocket, {
  Browsers,
  DisconnectReason,
  WASocket,
  fetchLatestWaWebVersion,
  makeCacheableSignalKeyStore,
  useMultiFileAuthState,
  downloadMediaMessage,
  type WAMessage,
} from '@whiskeysockets/baileys';
import express from 'express';
import pino from 'pino';
import QRCode from 'qrcode';

// ─── Configuration ───────────────────────────────────────────────────────────

const PORT = parseInt(process.env.PORT || '7891', 10);
const AUTH_DIR = process.env.AUTH_DIR || path.join(
  process.env.HOME || '~',
  '.autoclawd',
  'whatsapp',
  'auth',
);
const MEDIA_DIR = process.env.MEDIA_DIR || path.join(
  process.env.HOME || '~',
  '.autoclawd',
  'whatsapp',
  'media',
);

// ─── Logger ──────────────────────────────────────────────────────────────────

const logger = pino({ level: 'warn' });

// ─── Types ───────────────────────────────────────────────────────────────────

interface BufferedMessage {
  id: string;
  jid: string;
  sender: string;
  senderName: string;
  text: string;
  timestamp: number; // Unix seconds
  mediaPath?: string;
  isVoiceNote: boolean;
  isFromMe: boolean;
}

type ConnectionState = 'disconnected' | 'connecting' | 'waiting_for_qr' | 'connected';

// ─── State ───────────────────────────────────────────────────────────────────

let sock: WASocket | null = null;
let connectionState: ConnectionState = 'disconnected';
let phoneNumber: string | null = null;
let currentQR: string | null = null; // raw QR string from Baileys
let currentQRBase64: string | null = null; // PNG base64
let messageBuffer: BufferedMessage[] = [];
let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
let isShuttingDown = false;

// Track message IDs sent by the bot (via POST /send) so we can exclude them from polls
const botSentMessageIDs: Set<string> = new Set();

// ─── WhatsApp Connection ─────────────────────────────────────────────────────

async function connectWhatsApp(): Promise<void> {
  if (isShuttingDown) return;

  fs.mkdirSync(AUTH_DIR, { recursive: true });
  fs.mkdirSync(MEDIA_DIR, { recursive: true });

  connectionState = 'connecting';
  currentQR = null;
  currentQRBase64 = null;

  const { state, saveCreds } = await useMultiFileAuthState(AUTH_DIR);

  const { version } = await fetchLatestWaWebVersion({}).catch((err) => {
    logger.warn({ err }, 'Failed to fetch WA Web version, using default');
    return { version: undefined };
  });

  sock = makeWASocket({
    version,
    auth: {
      creds: state.creds,
      keys: makeCacheableSignalKeyStore(state.keys, logger),
    },
    printQRInTerminal: false,
    logger,
    browser: Browsers.macOS('Chrome'),
  });

  sock.ev.on('connection.update', async (update) => {
    const { connection, lastDisconnect, qr } = update;

    if (qr) {
      connectionState = 'waiting_for_qr';
      currentQR = qr;
      // Generate PNG base64
      try {
        currentQRBase64 = await QRCode.toDataURL(qr, {
          width: 256,
          margin: 2,
          color: { dark: '#000000', light: '#ffffff' },
        });
      } catch {
        currentQRBase64 = null;
      }
      console.log('[WhatsApp] QR code available — scan from Settings');
    }

    if (connection === 'close') {
      connectionState = 'disconnected';
      phoneNumber = null;
      currentQR = null;
      currentQRBase64 = null;

      const reason = (lastDisconnect?.error as any)?.output?.statusCode;
      const shouldReconnect = reason !== DisconnectReason.loggedOut && !isShuttingDown;

      console.log(`[WhatsApp] Connection closed (reason: ${reason}), reconnect: ${shouldReconnect}`);

      if (shouldReconnect) {
        // Reconnect with exponential backoff capped at 30s
        const delay = Math.min(5000, 1000);
        reconnectTimer = setTimeout(() => {
          connectWhatsApp().catch((err) => {
            console.error('[WhatsApp] Reconnect failed:', err);
          });
        }, delay);
      }
    }

    if (connection === 'open') {
      connectionState = 'connected';
      currentQR = null;
      currentQRBase64 = null;

      // Extract phone number
      if (sock?.user) {
        phoneNumber = sock.user.id.split(':')[0];
      }

      // Announce presence
      sock?.sendPresenceUpdate('available').catch(() => {});

      console.log(`[WhatsApp] Connected as ${phoneNumber}`);
    }
  });

  sock.ev.on('creds.update', saveCreds);

  sock.ev.on('messages.upsert', async ({ messages }) => {
    for (const msg of messages) {
      if (!msg.message) continue;
      const rawJid = msg.key.remoteJid;
      if (!rawJid || rawJid === 'status@broadcast') continue;

      // Only process self-chat (Message Yourself) and individual DMs.
      // Groups use @g.us JIDs — filter them out at the source to prevent
      // group messages from ever entering the AutoClawd pipeline.
      if (rawJid.endsWith('@g.us') || rawJid.endsWith('@broadcast')) {
        continue;
      }

      // Skip messages sent by the bot itself (via POST /send)
      if (msg.key.id && botSentMessageIDs.has(msg.key.id)) {
        botSentMessageIDs.delete(msg.key.id); // clean up
        continue;
      }

      const timestamp = Number(msg.messageTimestamp) || Math.floor(Date.now() / 1000);
      const sender = msg.key.participant || msg.key.remoteJid || '';
      const senderName = msg.pushName || sender.split('@')[0];
      const isFromMe = msg.key.fromMe || false;

      // Extract text content
      let text =
        msg.message?.conversation ||
        msg.message?.extendedTextMessage?.text ||
        msg.message?.imageMessage?.caption ||
        msg.message?.videoMessage?.caption ||
        '';

      // Check for voice note / audio
      const isVoiceNote = !!(
        msg.message?.audioMessage ||
        msg.message?.pttMessage // push-to-talk = voice note
      );

      let mediaPath: string | undefined;

      // Download voice notes for transcription
      if (isVoiceNote) {
        try {
          const buffer = await downloadMediaMessage(
            msg as WAMessage,
            'buffer',
            {},
            {
              logger,
              reuploadRequest: sock!.updateMediaMessage,
            },
          );
          const filename = `voice-${msg.key.id}-${timestamp}.ogg`;
          mediaPath = path.join(MEDIA_DIR, filename);
          fs.writeFileSync(mediaPath, buffer as Buffer);
          text = '[Voice Note]';
          console.log(`[WhatsApp] Voice note saved: ${mediaPath}`);
        } catch (err) {
          console.error('[WhatsApp] Failed to download voice note:', err);
          text = '[Voice Note - download failed]';
        }
      }

      // Skip empty non-voice messages
      if (!text && !isVoiceNote) continue;

      const buffered: BufferedMessage = {
        id: msg.key.id || `${timestamp}-${Math.random().toString(36).slice(2)}`,
        jid: rawJid,
        sender,
        senderName,
        text,
        timestamp,
        mediaPath,
        isVoiceNote,
        isFromMe,
      };

      messageBuffer.push(buffered);

      // Cap buffer at 1000 messages
      if (messageBuffer.length > 1000) {
        messageBuffer = messageBuffer.slice(-500);
      }

      console.log(`[WhatsApp] Message from ${senderName}: ${text.slice(0, 50)}${text.length > 50 ? '...' : ''}`);
    }
  });
}

// ─── Express Server ──────────────────────────────────────────────────────────

const app = express();
app.use(express.json());

// Health check
app.get('/health', (_req, res) => {
  res.json({
    status: connectionState,
    phoneNumber,
    bufferedMessages: messageBuffer.length,
    hasQR: !!currentQRBase64,
  });
});

// QR code for linking
app.get('/qr', (_req, res) => {
  if (connectionState === 'connected') {
    res.json({ status: 'already_connected', phoneNumber });
    return;
  }
  if (!currentQRBase64) {
    res.json({ status: connectionState, qr: null });
    return;
  }
  res.json({
    status: 'waiting_for_qr',
    qr: currentQRBase64,
  });
});

// Poll messages since timestamp
app.get('/messages', (req, res) => {
  const since = parseFloat(req.query.since as string) || 0;
  const messages = messageBuffer.filter((m) => m.timestamp > since);
  res.json({ messages });
});

// Send message
app.post('/send', async (req, res) => {
  const { jid, text } = req.body;
  if (!jid || !text) {
    res.status(400).json({ error: 'jid and text are required' });
    return;
  }
  if (!sock || connectionState !== 'connected') {
    res.status(503).json({ error: 'WhatsApp not connected' });
    return;
  }
  try {
    const sentMsg = await sock.sendMessage(jid, { text });
    // Track this message ID so we don't pick it up as a new incoming message
    if (sentMsg?.key?.id) {
      botSentMessageIDs.add(sentMsg.key.id);
      // Cap the set size
      if (botSentMessageIDs.size > 200) {
        const entries = [...botSentMessageIDs];
        entries.slice(0, 100).forEach((id) => botSentMessageIDs.delete(id));
      }
    }
    res.json({ success: true });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// Disconnect and optionally clear auth
app.post('/disconnect', async (req, res) => {
  const { clearAuth } = req.body || {};
  try {
    if (sock) {
      sock.end(undefined);
      sock = null;
    }
    connectionState = 'disconnected';
    phoneNumber = null;
    currentQR = null;
    currentQRBase64 = null;

    if (clearAuth) {
      fs.rmSync(AUTH_DIR, { recursive: true, force: true });
      console.log('[WhatsApp] Auth cleared');
    }

    res.json({ success: true });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// Connect (or reconnect)
app.post('/connect', async (_req, res) => {
  if (connectionState === 'connected') {
    res.json({ status: 'already_connected', phoneNumber });
    return;
  }
  try {
    await connectWhatsApp();
    res.json({ status: connectionState });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// ─── Start ───────────────────────────────────────────────────────────────────

app.listen(PORT, '127.0.0.1', () => {
  console.log(`[AutoClawd WhatsApp Sidecar] Listening on http://127.0.0.1:${PORT}`);
});

// Auto-connect if auth state exists
if (fs.existsSync(path.join(AUTH_DIR, 'creds.json'))) {
  console.log('[WhatsApp] Auth state found, auto-connecting...');
  connectWhatsApp().catch((err) => {
    console.error('[WhatsApp] Auto-connect failed:', err);
  });
} else {
  console.log('[WhatsApp] No auth state — waiting for /connect request');
}

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('[WhatsApp] SIGTERM received, shutting down...');
  isShuttingDown = true;
  if (reconnectTimer) clearTimeout(reconnectTimer);
  if (sock) sock.end(undefined);
  process.exit(0);
});

process.on('SIGINT', () => {
  isShuttingDown = true;
  if (reconnectTimer) clearTimeout(reconnectTimer);
  if (sock) sock.end(undefined);
  process.exit(0);
});
