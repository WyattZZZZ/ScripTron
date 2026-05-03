/// Credential storage: macOS Keychain on macOS, encrypted JSON file elsewhere.
use crate::{AuthError, Credentials, Provider};
use std::path::Path;

#[cfg(target_os = "macos")]
const SERVICE: &str = "com.scriptron.app";

// ── macOS Keychain ────────────────────────────────────────────────────────────

#[cfg(target_os = "macos")]
pub fn store(provider: &Provider, creds: &Credentials, _dir: &Path) -> Result<(), AuthError> {
    use security_framework::passwords::set_generic_password;
    let json = serde_json::to_string(creds).map_err(AuthError::Json)?;
    set_generic_password(SERVICE, provider.id(), json.as_bytes())
        .map_err(|e| AuthError::Keychain(e.to_string()))
}

#[cfg(target_os = "macos")]
pub fn load(provider: &Provider, _dir: &Path) -> Result<Option<Credentials>, AuthError> {
    use security_framework::passwords::get_generic_password;
    match get_generic_password(SERVICE, provider.id()) {
        Ok(bytes) => {
            let creds: Credentials = serde_json::from_slice(&bytes).map_err(AuthError::Json)?;
            Ok(Some(creds))
        }
        Err(e) if e.code() == -25300 => Ok(None), // errSecItemNotFound
        Err(e) => Err(AuthError::Keychain(e.to_string())),
    }
}

#[cfg(target_os = "macos")]
pub fn delete(provider: &Provider, _dir: &Path) -> Result<(), AuthError> {
    use security_framework::passwords::delete_generic_password;
    delete_generic_password(SERVICE, provider.id()).map_err(|e| AuthError::Keychain(e.to_string()))
}

// ── File-based fallback (Linux / Windows / dev) ───────────────────────────────

#[cfg(not(target_os = "macos"))]
pub fn store(provider: &Provider, creds: &Credentials, dir: &Path) -> Result<(), AuthError> {
    std::fs::create_dir_all(dir)?;
    let path = dir.join(format!("{}.json", provider.id()));
    let json = serde_json::to_string_pretty(creds).map_err(AuthError::Json)?;
    std::fs::write(path, json)?;
    Ok(())
}

#[cfg(not(target_os = "macos"))]
pub fn load(provider: &Provider, dir: &Path) -> Result<Option<Credentials>, AuthError> {
    let path = dir.join(format!("{}.json", provider.id()));
    if !path.exists() {
        return Ok(None);
    }
    let raw = std::fs::read_to_string(path)?;
    let creds: Credentials = serde_json::from_str(&raw).map_err(AuthError::Json)?;
    Ok(Some(creds))
}

#[cfg(not(target_os = "macos"))]
pub fn delete(provider: &Provider, dir: &Path) -> Result<(), AuthError> {
    let path = dir.join(format!("{}.json", provider.id()));
    if path.exists() {
        std::fs::remove_file(path)?;
    }
    Ok(())
}
