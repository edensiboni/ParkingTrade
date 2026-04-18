import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

let _cachedAccessToken: string | null = null
let _tokenExpiresAt = 0

function base64url(buf: ArrayBuffer): string {
  const bytes = new Uint8Array(buf)
  let str = ''
  for (const b of bytes) str += String.fromCharCode(b)
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

async function getAccessToken(serviceAccount: {
  client_email: string
  private_key: string
  project_id: string
}): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  if (_cachedAccessToken && now < _tokenExpiresAt - 30) {
    return _cachedAccessToken
  }

  const header = base64url(new TextEncoder().encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })))
  const payload = base64url(
    new TextEncoder().encode(
      JSON.stringify({
        iss: serviceAccount.client_email,
        scope: 'https://www.googleapis.com/auth/firebase.messaging',
        aud: 'https://oauth2.googleapis.com/token',
        iat: now,
        exp: now + 3600,
      }),
    ),
  )

  const pem = serviceAccount.private_key
  const pemBody = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\n/g, '')
  const keyBuf = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0))

  const key = await crypto.subtle.importKey(
    'pkcs8',
    keyBuf,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )

  const sigInput = new TextEncoder().encode(`${header}.${payload}`)
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, sigInput)
  const jwt = `${header}.${payload}.${base64url(sig)}`

  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  })

  if (!tokenRes.ok) {
    const errText = await tokenRes.text()
    throw new Error(`OAuth token exchange failed: ${tokenRes.status} ${errText}`)
  }

  const tokenData = await tokenRes.json()
  _cachedAccessToken = tokenData.access_token
  _tokenExpiresAt = now + (tokenData.expires_in ?? 3600)
  return _cachedAccessToken!
}

export async function sendPushToUser(
  supabaseClient: ReturnType<typeof createClient>,
  userId: string,
  title: string,
  body: string,
  data?: Record<string, string>,
) {
  const { data: tokens, error } = await supabaseClient
    .from('user_fcm_tokens')
    .select('token')
    .eq('user_id', userId)

  if (error || !tokens || tokens.length === 0) {
    console.log(`No FCM tokens for user ${userId}`)
    return
  }

  const serviceAccountJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
  if (!serviceAccountJson) {
    console.log('FIREBASE_SERVICE_ACCOUNT not configured — skipping push')
    return
  }

  let serviceAccount: { client_email: string; private_key: string; project_id: string }
  try {
    serviceAccount = JSON.parse(serviceAccountJson)
  } catch {
    console.error('Failed to parse FIREBASE_SERVICE_ACCOUNT JSON')
    return
  }

  let accessToken: string
  try {
    accessToken = await getAccessToken(serviceAccount)
  } catch (e) {
    console.error(`Failed to get FCM access token: ${e.message}`)
    return
  }

  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`

  for (const { token } of tokens) {
    try {
      const res = await fetch(fcmUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title, body },
            data: data ?? {},
          },
        }),
      })

      if (!res.ok) {
        const errBody = await res.text()
        console.error(`FCM v1 send failed for token ${token.substring(0, 10)}...: ${res.status} ${errBody}`)
      }
    } catch (e) {
      console.error(`FCM v1 send error: ${e.message}`)
    }
  }
}
