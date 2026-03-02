// r2-core/src/credentials.rs — Cross-platform credential storage for R2Drop
// Uses the OS keychain (macOS Keychain, Windows Credential Manager, Linux Secret Service)
// to store API tokens securely. Never writes tokens to disk.
//
// The service name matches the Swift KeychainManager so the CLI and macOS app
// share the same keychain entries.

use thiserror::Error;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Keychain service name — must match Swift's KeychainManager.SERVICE.
const SERVICE: &str = "com.superhumancorp.r2drop";

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

#[derive(Debug, Error)]
pub enum CredentialError {
    #[error("keyring error: {0}")]
    Keyring(#[from] keyring::Error),
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Save an API token for the given account name.
/// Overwrites any existing token for that account.
pub fn save_token(account: &str, token: &str) -> Result<(), CredentialError> {
    let entry = keyring::Entry::new(SERVICE, account)?;
    entry.set_password(token)?;
    Ok(())
}

/// Retrieve the API token for the given account name.
/// Returns an error if no token is stored.
pub fn get_token(account: &str) -> Result<String, CredentialError> {
    let entry = keyring::Entry::new(SERVICE, account)?;
    let password = entry.get_password()?;
    Ok(password)
}

/// Delete the stored API token for the given account name.
pub fn delete_token(account: &str) -> Result<(), CredentialError> {
    let entry = keyring::Entry::new(SERVICE, account)?;
    entry.delete_credential()?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn service_name_matches_swift() {
        // The constant must stay in sync with Swift's KeychainManager.
        assert_eq!(SERVICE, "com.superhumancorp.r2drop");
    }

    #[test]
    fn credential_error_displays_message() {
        let err = CredentialError::Keyring(keyring::Error::NoEntry);
        let msg = format!("{err}");
        assert!(msg.contains("keyring error"));
    }
}
