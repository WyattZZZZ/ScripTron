/// Desktop OAuth 2.0 PKCE flow.
///
/// Works for any provider that supports PKCE and a localhost redirect URI.
/// The flow:
///   1. Generate code_verifier + code_challenge.
///   2. Open the browser at the provider's auth URL.
///   3. Spin up a one-shot TCP listener on localhost to catch the redirect.
///   4. Exchange the code for tokens.
///   5. Return `Credentials`.

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use rand::Rng;
use reqwest::Client;
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::net::TcpListener;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener as TokioListener;

use crate::{AuthError, Credentials};

pub struct PkceFlow {
    pub auth_url: String,
    pub token_url: String,
    pub client_id: String,
    /// Required by some providers (Anthropic). Treat as non-confidential on desktop.
    pub client_secret: Option<String>,
    pub scopes: Vec<String>,
}

impl PkceFlow {
    /// Run the full PKCE flow. Opens the user's browser and waits for the redirect.
    pub async fn run(&self) -> Result<Credentials, AuthError> {
        let (verifier, challenge) = generate_pkce_pair();

        // Find a free port
        let port = {
            let listener = TcpListener::bind("127.0.0.1:0").map_err(AuthError::Io)?;
            listener.local_addr().map_err(AuthError::Io)?.port()
        };
        let redirect_uri = format!("http://127.0.0.1:{}/callback", port);

        let state: String = rand::thread_rng()
            .sample_iter(&rand::distributions::Alphanumeric)
            .take(16)
            .map(char::from)
            .collect();

        // Build the authorisation URL
        let mut auth_url = url::Url::parse(&self.auth_url)
            .map_err(|e| AuthError::OAuth { code: "bad_url".into(), description: e.to_string() })?;
        {
            let mut q = auth_url.query_pairs_mut();
            q.append_pair("response_type", "code");
            q.append_pair("client_id", &self.client_id);
            q.append_pair("redirect_uri", &redirect_uri);
            q.append_pair("scope", &self.scopes.join(" "));
            q.append_pair("state", &state);
            q.append_pair("code_challenge", &challenge);
            q.append_pair("code_challenge_method", "S256");
        }

        // Open browser — on macOS this is `open`, on Linux `xdg-open`
        let open_cmd = if cfg!(target_os = "macos") { "open" } else { "xdg-open" };
        tokio::process::Command::new(open_cmd)
            .arg(auth_url.as_str())
            .spawn()
            .map_err(AuthError::Io)?;

        // Wait for the redirect
        let code = await_redirect(port, &state).await?;

        // Exchange code for tokens
        let tokens = exchange_code(
            &code,
            &verifier,
            &redirect_uri,
            &self.token_url,
            &self.client_id,
            self.client_secret.as_deref(),
        )
        .await?;

        Ok(tokens)
    }
}

fn generate_pkce_pair() -> (String, String) {
    let verifier: String = rand::thread_rng()
        .sample_iter(&rand::distributions::Alphanumeric)
        .take(64)
        .map(char::from)
        .collect();
    let hash = Sha256::digest(verifier.as_bytes());
    let challenge = URL_SAFE_NO_PAD.encode(hash);
    (verifier, challenge)
}

async fn await_redirect(port: u16, expected_state: &str) -> Result<String, AuthError> {
    let listener = TokioListener::bind(format!("127.0.0.1:{}", port))
        .await
        .map_err(AuthError::Io)?;

    let (mut stream, _) = listener.accept().await.map_err(AuthError::Io)?;

    let mut request = String::new();
    let mut buf = [0u8; 4096];
    loop {
        let n = stream.read(&mut buf).await.map_err(AuthError::Io)?;
        if n == 0 {
            break;
        }
        request.push_str(&String::from_utf8_lossy(&buf[..n]));
        if request.contains("\r\n\r\n") {
            break;
        }
    }

    // Parse the GET line: GET /callback?code=...&state=... HTTP/1.1
    let query = request
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
        .and_then(|path| path.split_once('?').map(|(_, q)| q))
        .unwrap_or("");

    let params: std::collections::HashMap<_, _> = url::form_urlencoded::parse(query.as_bytes())
        .into_owned()
        .collect();

    // Validate state
    let returned_state = params.get("state").map(String::as_str).unwrap_or("");
    if returned_state != expected_state {
        let _ = stream
            .write_all(b"HTTP/1.1 400 Bad Request\r\n\r\nState mismatch.")
            .await;
        return Err(AuthError::OAuth {
            code: "state_mismatch".into(),
            description: "OAuth state parameter did not match".into(),
        });
    }

    let code = params
        .get("code")
        .cloned()
        .ok_or_else(|| AuthError::OAuth {
            code: "no_code".into(),
            description: params
                .get("error_description")
                .cloned()
                .unwrap_or_else(|| "No authorization code returned".into()),
        })?;

    // Respond to the browser
    let html = r#"HTTP/1.1 200 OK
Content-Type: text/html

<!DOCTYPE html>
<html>
<head><title>ScripTron — Connected</title></head>
<body style="font-family:sans-serif;text-align:center;padding:60px;background:#1a1a1a;color:#e0e0e0">
<h2>Connected successfully!</h2>
<p>You can close this tab and return to ScripTron.</p>
</body>
</html>"#;
    let _ = stream.write_all(html.as_bytes()).await;

    Ok(code)
}

#[derive(Deserialize)]
struct TokenResponse {
    access_token: String,
    refresh_token: Option<String>,
    expires_in: Option<i64>,
}

async fn exchange_code(
    code: &str,
    verifier: &str,
    redirect_uri: &str,
    token_url: &str,
    client_id: &str,
    client_secret: Option<&str>,
) -> Result<Credentials, AuthError> {
    let client = Client::new();
    let mut params = vec![
        ("grant_type", "authorization_code"),
        ("code", code),
        ("redirect_uri", redirect_uri),
        ("client_id", client_id),
        ("code_verifier", verifier),
    ];
    let secret_owned;
    if let Some(s) = client_secret {
        secret_owned = s.to_string();
        params.push(("client_secret", &secret_owned));
    }

    let resp = client
        .post(token_url)
        .form(&params)
        .send()
        .await
        .map_err(|e| AuthError::Network(e.to_string()))?;

    if !resp.status().is_success() {
        let body = resp.text().await.unwrap_or_default();
        return Err(AuthError::OAuth {
            code: "token_exchange_failed".into(),
            description: body,
        });
    }

    let token: TokenResponse = resp.json().await.map_err(|e| AuthError::Network(e.to_string()))?;

    let expires_at = token
        .expires_in
        .map(|secs| chrono::Utc::now().timestamp_millis() + secs * 1000);

    Ok(Credentials {
        access_token: token.access_token,
        refresh_token: token.refresh_token,
        expires_at,
    })
}
