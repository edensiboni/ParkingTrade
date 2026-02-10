/**
 * Send FCM (push) notifications to all tokens registered for a user.
 * Requires Supabase secrets: FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY
 * (from Firebase Console → Project settings → Service accounts → Generate new private key).
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const FCM_SEND_URL = (projectId: string) =>
  `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`
const OAUTH_TOKEN_URL = 'https://oauth2.googleapis.com/token'

async function getAccessToken(
  clientEmail: string,
  privateKeyPem: string
): Promise<string> {
  const pem = privateKeyPem.replace(/\\n/g, '\n')
  const pemContents = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .trim()
  const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0))

  const key = await crypto.subtle.importKey(
    'pkcs8',
    binaryDer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  )

  const now = Math.floor(Date.now() / 1000)
  const payload = {
    iss: clientEmail,
    sub: clientEmail,
    aud: OAUTH_TOKEN_URL,
    iat: now,
    exp: now + 3600,
  }
  const header = { alg: 'RS256', typ: 'JWT' }
  const encodedHeader = base64UrlEncode(JSON.stringify(header))
  const encodedPayload = base64UrlEncode(JSON.stringify(payload))
  const signatureInput = `${encodedHeader}.${encodedPayload}`

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(signatureInput)
  )
  const encodedSignature = base64UrlEncodeFromBuffer(signature)
  const jwt = `${signatureInput}.${encodedSignature}`

  const body = new URLSearchParams({
    grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
    assertion: jwt,
  })
  const res = await fetch(OAUTH_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`OAuth token failed: ${res.status} ${text}`)
  }
  const data = await res.json()
  return data.access_token
}

function base64UrlEncode(str: string): string {
  const bin = new TextEncoder().encode(str)
  return base64UrlEncodeFromBuffer(bin)
}

function base64UrlEncodeFromBuffer(buf: ArrayBuffer): string {
  const bytes = new Uint8Array(buf)
  let binary = ''
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i])
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

async function sendFcmMessage(
  projectId: string,
  accessToken: string,
  token: string,
  title: string,
  body: string,
  data?: Record<string, string>
): Promise<boolean> {
  const res = await fetch(FCM_SEND_URL(projectId), {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      message: {
        token,
        notification: { title, body },
        data: data || {},
      },
    }),
  })
  if (!res.ok) {
    const text = await res.text()
    console.error(`FCM send failed for token: ${res.status} ${text}`)
    return false
  }
  return true
}

export async function sendPushToUser(
  supabaseClient: ReturnType<typeof createClient>,
  userId: string,
  title: string,
  body: string,
  data?: Record<string, string>
): Promise<void> {
  const projectId = Deno.env.get('FIREBASE_PROJECT_ID')
  const clientEmail = Deno.env.get('FIREBASE_CLIENT_EMAIL')
  const privateKey = Deno.env.get('FIREBASE_PRIVATE_KEY')
  if (!projectId || !clientEmail || !privateKey) {
    console.warn('FCM not configured: set FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY')
    return
  }

  const { data: rows, error } = await supabaseClient
    .from('user_fcm_tokens')
    .select('token')
    .eq('user_id', userId)

  if (error || !rows?.length) return

  let accessToken: string
  try {
    accessToken = await getAccessToken(clientEmail, privateKey)
  } catch (e) {
    console.error('FCM OAuth failed:', e)
    return
  }

  for (const row of rows) {
    await sendFcmMessage(projectId, accessToken, row.token, title, body, data)
  }
}
