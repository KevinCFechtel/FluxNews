//! Versioned, encrypted configuration backup serialization. Parsing is pure and never mutates a
//! `FluxCore`, its SQLite store, or native platform state.

use std::collections::HashSet;

use aes_gcm::{
    Aes256Gcm, Nonce,
    aead::{Aead, KeyInit, Payload},
};
use argon2::{Algorithm, Argon2, Params, Version};
use base64::{Engine as _, engine::general_purpose::STANDARD};
use rand::{TryRng, rngs::SysRng};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::{
    domain::{
        CoreSettings, DeliveryMode, DetailRenderingMode, DownloadNetworkPolicy, DownloadRetention,
        FeedPreferences, ReadArticleRetention,
    },
    miniflux::normalize_installation_base,
};

pub const BACKUP_FORMAT_VERSION: u32 = 1;
const MAGIC: &str = "FLUX_CONFIG_BACKUP";
const MAX_BACKUP_BYTES: usize = 2 * 1024 * 1024;
const MAX_PAYLOAD_BYTES: usize = 1024 * 1024;
const MAX_PLATFORM_SETTINGS_BYTES: usize = 256 * 1024;
const MAX_FEED_PREFERENCES: usize = 10_000;
const MAX_STRING_BYTES: usize = 8 * 1024;
const SALT_BYTES: usize = 16;
const NONCE_BYTES: usize = 12;
const AUTH_TAG_BYTES: usize = 16;

/// Production Argon2id settings: 64 MiB memory, three passes, one lane. This is an interactive
/// desktop cost while materially resisting offline password guessing.
#[cfg(not(test))]
const PRODUCTION_MEMORY_KIB: u32 = 65_536;
#[cfg(not(test))]
const PRODUCTION_ITERATIONS: u32 = 3;
#[cfg(not(test))]
const PRODUCTION_PARALLELISM: u32 = 1;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BackupPlatform {
    Macos,
    Ios,
    Android,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BackupAccount {
    pub installation_base: String,
    pub api_key: String,
}

/// Native-owned settings carried as a versioned JSON object. `flux-core` does not inspect keys.
#[derive(Clone, Debug, PartialEq)]
pub struct PlatformSettingsPayload {
    pub schema_version: u32,
    pub data: Value,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ConfigBackupInput {
    pub platform: BackupPlatform,
    pub account: BackupAccount,
    pub core_settings: CoreSettings,
    pub feed_preferences: Vec<FeedPreferences>,
    pub platform_settings: PlatformSettingsPayload,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ConfigBackupRestoreModel {
    pub platform: BackupPlatform,
    pub account: BackupAccount,
    pub core_settings: CoreSettings,
    pub feed_preferences: Vec<FeedPreferences>,
    pub platform_settings: PlatformSettingsPayload,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ConfigBackupError {
    EmptyPassword,
    NotFluxBackup,
    UnsupportedVersion,
    PlatformMismatch,
    InvalidCryptoMetadata,
    DecryptionFailed,
    MalformedPayload,
    InvalidContents,
    InputTooLarge,
    Internal,
}

impl std::fmt::Display for ConfigBackupError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::EmptyPassword => "backup password must not be empty",
            Self::NotFluxBackup => "file is not a Flux configuration backup",
            Self::UnsupportedVersion => "backup format version is not supported",
            Self::PlatformMismatch => "backup was created for a different platform",
            Self::InvalidCryptoMetadata => "backup cryptographic metadata is invalid",
            Self::DecryptionFailed => "backup could not be decrypted or authenticated",
            Self::MalformedPayload => "backup encrypted payload is malformed",
            Self::InvalidContents => "backup contents are invalid",
            Self::InputTooLarge => "backup exceeds supported size limits",
            Self::Internal => "backup cryptographic operation failed",
        })
    }
}

impl std::error::Error for ConfigBackupError {}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Envelope {
    magic: String,
    version: u32,
    platform: BackupPlatform,
    crypto: String,
    kdf: KdfMetadata,
    salt: String,
    nonce: String,
    ciphertext: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct EnvelopeHeader {
    magic: String,
    version: u32,
    platform: BackupPlatform,
    crypto: String,
    kdf: KdfMetadata,
    salt: String,
    nonce: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct KdfMetadata {
    algorithm: String,
    memory_kib: u32,
    iterations: u32,
    parallelism: u32,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct PayloadV1 {
    account: AccountV1,
    core_settings: CoreSettingsV1,
    feed_preferences: Vec<FeedPreferencesV1>,
    platform_settings: PlatformSettingsV1,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct AccountV1 {
    installation_base: String,
    api_key: String,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct CoreSettingsV1 {
    retention_days: u16,
    delivery_mode: String,
    background_sync_enabled: bool,
    detail_character_limit: u32,
    #[serde(default)]
    download_network_policy: Option<String>,
    #[serde(default)]
    download_retention_days: Option<u32>,
    #[serde(default)]
    delete_after_playback: Option<bool>,
    #[serde(default)]
    auto_download_listening_list: Option<bool>,
    #[serde(default)]
    remove_completed_listening_list: Option<bool>,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct FeedPreferencesV1 {
    feed_id: i64,
    system_notifications_enabled: bool,
    detail_rendering: String,
    truncate_detail: bool,
    open_in_miniflux: bool,
    #[serde(default)]
    auto_download_audio: bool,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct PlatformSettingsV1 {
    schema_version: u32,
    data: Value,
}

/// Validates, serializes, and password-encrypts one platform's complete configurable state.
pub fn export_config_backup(
    input: ConfigBackupInput,
    password: &str,
) -> Result<Vec<u8>, ConfigBackupError> {
    if password.is_empty() {
        return Err(ConfigBackupError::EmptyPassword);
    }
    let platform = input.platform;
    let payload = to_payload(input)?;
    let plaintext = serde_json::to_vec(&payload).map_err(|_| ConfigBackupError::Internal)?;
    if plaintext.len() > MAX_PAYLOAD_BYTES {
        return Err(ConfigBackupError::InputTooLarge);
    }
    let mut salt = [0u8; SALT_BYTES];
    let mut nonce = [0u8; NONCE_BYTES];
    SysRng
        .try_fill_bytes(&mut salt)
        .map_err(|_| ConfigBackupError::Internal)?;
    SysRng
        .try_fill_bytes(&mut nonce)
        .map_err(|_| ConfigBackupError::Internal)?;
    let kdf = production_kdf();
    let header = EnvelopeHeader {
        magic: MAGIC.into(),
        version: BACKUP_FORMAT_VERSION,
        platform,
        crypto: "aes-256-gcm".into(),
        kdf: kdf.clone(),
        salt: STANDARD.encode(salt),
        nonce: STANDARD.encode(nonce),
    };
    let key = derive_key(password, &salt, &kdf)?;
    let aad = header_bytes(&header)?;
    let ciphertext = Aes256Gcm::new_from_slice(&key)
        .map_err(|_| ConfigBackupError::Internal)?
        .encrypt(
            &Nonce::from(nonce),
            Payload {
                msg: &plaintext,
                aad: &aad,
            },
        )
        .map_err(|_| ConfigBackupError::Internal)?;
    let envelope = Envelope {
        magic: header.magic,
        version: header.version,
        platform: header.platform,
        crypto: header.crypto,
        kdf: header.kdf,
        salt: header.salt,
        nonce: header.nonce,
        ciphertext: STANDARD.encode(ciphertext),
    };
    serde_json::to_vec(&envelope).map_err(|_| ConfigBackupError::Internal)
}

/// Parses, authenticates, decrypts, and validates a backup without changing any application state.
pub fn parse_config_backup(
    bytes: &[u8],
    password: &str,
    expected_platform: BackupPlatform,
) -> Result<ConfigBackupRestoreModel, ConfigBackupError> {
    if password.is_empty() {
        return Err(ConfigBackupError::EmptyPassword);
    }
    if bytes.len() > MAX_BACKUP_BYTES {
        return Err(ConfigBackupError::InputTooLarge);
    }
    let envelope: Envelope =
        serde_json::from_slice(bytes).map_err(|_| ConfigBackupError::NotFluxBackup)?;
    if envelope.magic != MAGIC {
        return Err(ConfigBackupError::NotFluxBackup);
    }
    if envelope.version != BACKUP_FORMAT_VERSION {
        return Err(ConfigBackupError::UnsupportedVersion);
    }
    if envelope.platform != expected_platform {
        return Err(ConfigBackupError::PlatformMismatch);
    }
    let salt = decode_exact(&envelope.salt, SALT_BYTES)?;
    let nonce: [u8; NONCE_BYTES] = decode_exact(&envelope.nonce, NONCE_BYTES)?
        .try_into()
        .map_err(|_| ConfigBackupError::InvalidCryptoMetadata)?;
    validate_kdf(&envelope.kdf)?;
    if envelope.crypto != "aes-256-gcm" {
        return Err(ConfigBackupError::InvalidCryptoMetadata);
    }
    let ciphertext = STANDARD
        .decode(&envelope.ciphertext)
        .map_err(|_| ConfigBackupError::InvalidCryptoMetadata)?;
    if !(AUTH_TAG_BYTES..=MAX_PAYLOAD_BYTES + AUTH_TAG_BYTES).contains(&ciphertext.len()) {
        return Err(ConfigBackupError::InputTooLarge);
    }
    let header = EnvelopeHeader {
        magic: envelope.magic,
        version: envelope.version,
        platform: envelope.platform,
        crypto: envelope.crypto,
        kdf: envelope.kdf,
        salt: envelope.salt,
        nonce: envelope.nonce,
    };
    let key = derive_key(password, &salt, &header.kdf)?;
    let aad = header_bytes(&header)?;
    let plaintext = Aes256Gcm::new_from_slice(&key)
        .map_err(|_| ConfigBackupError::Internal)?
        .decrypt(
            &Nonce::from(nonce),
            Payload {
                msg: &ciphertext,
                aad: &aad,
            },
        )
        .map_err(|_| ConfigBackupError::DecryptionFailed)?;
    let payload: PayloadV1 =
        serde_json::from_slice(&plaintext).map_err(|_| ConfigBackupError::MalformedPayload)?;
    from_payload(header.platform, payload)
}

fn to_payload(input: ConfigBackupInput) -> Result<PayloadV1, ConfigBackupError> {
    let canonical_base = validate_account(&input.account)?;
    validate_settings(&input.core_settings)?;
    validate_platform_settings(&input.platform_settings)?;
    validate_feed_preferences(&input.feed_preferences)?;
    Ok(PayloadV1 {
        account: AccountV1 {
            installation_base: canonical_base,
            api_key: input.account.api_key,
        },
        core_settings: CoreSettingsV1 {
            retention_days: input.core_settings.retention.days() as u16,
            delivery_mode: match input.core_settings.delivery_mode {
                DeliveryMode::Live => "live",
                DeliveryMode::Deferred => "deferred",
            }
            .into(),
            background_sync_enabled: input.core_settings.background_sync_enabled,
            detail_character_limit: input.core_settings.detail_character_limit,
            download_network_policy: Some(
                match input.core_settings.download_network_policy {
                    DownloadNetworkPolicy::AnyNetwork => "any_network",
                    DownloadNetworkPolicy::UnmeteredOnly => "unmetered_only",
                }
                .into(),
            ),
            download_retention_days: match input.core_settings.download_retention {
                DownloadRetention::Forever => None,
                DownloadRetention::Days(days) => Some(days),
            },
            delete_after_playback: Some(input.core_settings.delete_after_playback),
            auto_download_listening_list: Some(input.core_settings.auto_download_listening_list),
            remove_completed_listening_list: Some(
                input.core_settings.remove_completed_listening_list,
            ),
        },
        feed_preferences: input
            .feed_preferences
            .into_iter()
            .map(|preference| FeedPreferencesV1 {
                feed_id: preference.feed_id,
                system_notifications_enabled: preference.system_notifications_enabled,
                detail_rendering: match preference.detail_rendering {
                    DetailRenderingMode::Rendered => "rendered",
                    DetailRenderingMode::TextOnly => "text_only",
                }
                .into(),
                truncate_detail: preference.truncate_detail,
                open_in_miniflux: preference.open_in_miniflux,
                auto_download_audio: preference.auto_download_audio,
            })
            .collect(),
        platform_settings: PlatformSettingsV1 {
            schema_version: input.platform_settings.schema_version,
            data: input.platform_settings.data,
        },
    })
}

fn from_payload(
    platform: BackupPlatform,
    payload: PayloadV1,
) -> Result<ConfigBackupRestoreModel, ConfigBackupError> {
    let account = BackupAccount {
        installation_base: payload.account.installation_base,
        api_key: payload.account.api_key,
    };
    let canonical_base = validate_account(&account)?;
    if canonical_base != account.installation_base {
        return Err(ConfigBackupError::InvalidContents);
    }
    let settings = CoreSettings {
        retention: match payload.core_settings.retention_days {
            30 => ReadArticleRetention::Days30,
            60 => ReadArticleRetention::Days60,
            90 => ReadArticleRetention::Days90,
            180 => ReadArticleRetention::Days180,
            365 => ReadArticleRetention::Days365,
            _ => return Err(ConfigBackupError::InvalidContents),
        },
        delivery_mode: match payload.core_settings.delivery_mode.as_str() {
            "live" => DeliveryMode::Live,
            "deferred" => DeliveryMode::Deferred,
            _ => return Err(ConfigBackupError::InvalidContents),
        },
        background_sync_enabled: payload.core_settings.background_sync_enabled,
        detail_character_limit: payload.core_settings.detail_character_limit,
        download_network_policy: match payload.core_settings.download_network_policy.as_deref() {
            None | Some("any_network") => DownloadNetworkPolicy::AnyNetwork,
            Some("unmetered_only") => DownloadNetworkPolicy::UnmeteredOnly,
            _ => return Err(ConfigBackupError::InvalidContents),
        },
        download_retention: match payload.core_settings.download_retention_days {
            None => DownloadRetention::Forever,
            Some(days) if days > 0 => DownloadRetention::Days(days),
            Some(_) => return Err(ConfigBackupError::InvalidContents),
        },
        delete_after_playback: payload.core_settings.delete_after_playback.unwrap_or(false),
        auto_download_listening_list: payload
            .core_settings
            .auto_download_listening_list
            .unwrap_or(false),
        remove_completed_listening_list: payload
            .core_settings
            .remove_completed_listening_list
            .unwrap_or(false),
    };
    validate_settings(&settings)?;
    let preferences = payload
        .feed_preferences
        .into_iter()
        .map(|preference| {
            Ok(FeedPreferences {
                feed_id: preference.feed_id,
                system_notifications_enabled: preference.system_notifications_enabled,
                detail_rendering: match preference.detail_rendering.as_str() {
                    "rendered" => DetailRenderingMode::Rendered,
                    "text_only" => DetailRenderingMode::TextOnly,
                    _ => return Err(ConfigBackupError::InvalidContents),
                },
                truncate_detail: preference.truncate_detail,
                open_in_miniflux: preference.open_in_miniflux,
                auto_download_audio: preference.auto_download_audio,
            })
        })
        .collect::<Result<Vec<_>, ConfigBackupError>>()?;
    validate_feed_preferences(&preferences)?;
    let platform_settings = PlatformSettingsPayload {
        schema_version: payload.platform_settings.schema_version,
        data: payload.platform_settings.data,
    };
    validate_platform_settings(&platform_settings)?;
    Ok(ConfigBackupRestoreModel {
        platform,
        account,
        core_settings: settings,
        feed_preferences: preferences,
        platform_settings,
    })
}

fn validate_account(account: &BackupAccount) -> Result<String, ConfigBackupError> {
    if account.installation_base.is_empty()
        || account.installation_base.len() > MAX_STRING_BYTES
        || account.api_key.is_empty()
        || account.api_key.len() > MAX_STRING_BYTES
    {
        return Err(ConfigBackupError::InvalidContents);
    }
    normalize_installation_base(&account.installation_base)
        .map_err(|_| ConfigBackupError::InvalidContents)
}

fn validate_settings(settings: &CoreSettings) -> Result<(), ConfigBackupError> {
    if !matches!(settings.detail_character_limit, 5_000 | 10_000 | 20_000) {
        return Err(ConfigBackupError::InvalidContents);
    }
    Ok(())
}

fn validate_feed_preferences(preferences: &[FeedPreferences]) -> Result<(), ConfigBackupError> {
    if preferences.len() > MAX_FEED_PREFERENCES
        || preferences.iter().any(|preference| preference.feed_id <= 0)
    {
        return Err(ConfigBackupError::InvalidContents);
    }
    let mut ids = HashSet::with_capacity(preferences.len());
    if preferences
        .iter()
        .any(|preference| !ids.insert(preference.feed_id))
    {
        return Err(ConfigBackupError::InvalidContents);
    }
    Ok(())
}

fn validate_platform_settings(settings: &PlatformSettingsPayload) -> Result<(), ConfigBackupError> {
    if settings.schema_version == 0
        || !settings.data.is_object()
        || serde_json::to_vec(&settings.data)
            .map_err(|_| ConfigBackupError::InvalidContents)?
            .len()
            > MAX_PLATFORM_SETTINGS_BYTES
    {
        return Err(ConfigBackupError::InvalidContents);
    }
    Ok(())
}

fn validate_kdf(kdf: &KdfMetadata) -> Result<(), ConfigBackupError> {
    if kdf.algorithm != "argon2id"
        || !(1_024..=131_072).contains(&kdf.memory_kib)
        || !(1..=10).contains(&kdf.iterations)
        || !(1..=4).contains(&kdf.parallelism)
    {
        return Err(ConfigBackupError::InvalidCryptoMetadata);
    }
    Ok(())
}

fn derive_key(
    password: &str,
    salt: &[u8],
    kdf: &KdfMetadata,
) -> Result<[u8; 32], ConfigBackupError> {
    let params = Params::new(kdf.memory_kib, kdf.iterations, kdf.parallelism, Some(32))
        .map_err(|_| ConfigBackupError::InvalidCryptoMetadata)?;
    let mut key = [0u8; 32];
    Argon2::new(Algorithm::Argon2id, Version::V0x13, params)
        .hash_password_into(password.as_bytes(), salt, &mut key)
        .map_err(|_| ConfigBackupError::Internal)?;
    Ok(key)
}

fn decode_exact(value: &str, expected_len: usize) -> Result<Vec<u8>, ConfigBackupError> {
    let decoded = STANDARD
        .decode(value)
        .map_err(|_| ConfigBackupError::InvalidCryptoMetadata)?;
    if decoded.len() != expected_len {
        return Err(ConfigBackupError::InvalidCryptoMetadata);
    }
    Ok(decoded)
}

fn header_bytes(header: &EnvelopeHeader) -> Result<Vec<u8>, ConfigBackupError> {
    serde_json::to_vec(header).map_err(|_| ConfigBackupError::Internal)
}

#[cfg(test)]
fn production_kdf() -> KdfMetadata {
    // Unit tests exercise the same format with a deliberately cheaper test-only KDF.
    KdfMetadata {
        algorithm: "argon2id".into(),
        memory_kib: 1_024,
        iterations: 1,
        parallelism: 1,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn input() -> ConfigBackupInput {
        ConfigBackupInput {
            platform: BackupPlatform::Macos,
            account: BackupAccount {
                installation_base: "https://secret-backup-test.example.com/miniflux/v1".into(),
                api_key: "SUPER-SECRET-FLUX-API-KEY-12345".into(),
            },
            core_settings: CoreSettings {
                retention: ReadArticleRetention::Days365,
                delivery_mode: DeliveryMode::Live,
                background_sync_enabled: false,
                detail_character_limit: 20_000,
                ..CoreSettings::default()
            },
            feed_preferences: vec![
                FeedPreferences {
                    feed_id: 123,
                    system_notifications_enabled: true,
                    detail_rendering: DetailRenderingMode::TextOnly,
                    truncate_detail: true,
                    open_in_miniflux: true,
                    auto_download_audio: false,
                },
                FeedPreferences {
                    feed_id: 999_999,
                    system_notifications_enabled: false,
                    detail_rendering: DetailRenderingMode::Rendered,
                    truncate_detail: false,
                    open_in_miniflux: false,
                    auto_download_audio: false,
                },
            ],
            platform_settings: PlatformSettingsPayload {
                schema_version: 1,
                data: json!({ "marker": "PRIVATE-PLATFORM-SETTING-MARKER", "nested": { "enabled": true } }),
            },
        }
    }

    fn exported() -> Vec<u8> {
        export_config_backup(input(), "password").unwrap()
    }

    fn envelope(bytes: &[u8]) -> Envelope {
        serde_json::from_slice(bytes).unwrap()
    }

    fn encode(envelope: Envelope) -> Vec<u8> {
        serde_json::to_vec(&envelope).unwrap()
    }

    fn rewrite_payload(bytes: &[u8], edit: impl FnOnce(&mut Value)) -> Vec<u8> {
        let mut envelope = envelope(bytes);
        let salt = STANDARD.decode(&envelope.salt).unwrap();
        let nonce: [u8; NONCE_BYTES] = STANDARD
            .decode(&envelope.nonce)
            .unwrap()
            .try_into()
            .unwrap();
        let header = EnvelopeHeader {
            magic: envelope.magic.clone(),
            version: envelope.version,
            platform: envelope.platform,
            crypto: envelope.crypto.clone(),
            kdf: envelope.kdf.clone(),
            salt: envelope.salt.clone(),
            nonce: envelope.nonce.clone(),
        };
        let key = derive_key("password", &salt, &header.kdf).unwrap();
        let plaintext = Aes256Gcm::new_from_slice(&key)
            .unwrap()
            .decrypt(
                &Nonce::from(nonce),
                Payload {
                    msg: &STANDARD.decode(&envelope.ciphertext).unwrap(),
                    aad: &header_bytes(&header).unwrap(),
                },
            )
            .unwrap();
        let mut payload: Value = serde_json::from_slice(&plaintext).unwrap();
        edit(&mut payload);
        envelope.ciphertext = STANDARD.encode(
            Aes256Gcm::new_from_slice(&key)
                .unwrap()
                .encrypt(
                    &Nonce::from(nonce),
                    Payload {
                        msg: &serde_json::to_vec(&payload).unwrap(),
                        aad: &header_bytes(&header).unwrap(),
                    },
                )
                .unwrap(),
        );
        encode(envelope)
    }

    #[test]
    fn full_v1_roundtrip_is_canonical_and_accepts_orphan_feed_ids() {
        let restored = parse_config_backup(&exported(), "password", BackupPlatform::Macos).unwrap();
        assert_eq!(
            restored.account.installation_base,
            "https://secret-backup-test.example.com/miniflux"
        );
        assert_eq!(restored.account.api_key, "SUPER-SECRET-FLUX-API-KEY-12345");
        assert_eq!(restored.core_settings, input().core_settings);
        assert_eq!(restored.feed_preferences, input().feed_preferences);
        assert_eq!(restored.platform_settings, input().platform_settings);
    }

    #[test]
    fn encryption_uses_fresh_randomness_and_hides_plaintext_secrets() {
        let first = exported();
        let second = exported();
        assert_ne!(first, second);
        for secret in [
            "https://secret-backup-test.example.com/miniflux",
            "SUPER-SECRET-FLUX-API-KEY-12345",
            "PRIVATE-PLATFORM-SETTING-MARKER",
        ] {
            assert!(
                !first
                    .windows(secret.len())
                    .any(|window| window == secret.as_bytes())
            );
        }
    }

    #[test]
    fn password_and_ciphertext_tampering_fail_authentication() {
        let bytes = exported();
        assert_eq!(
            parse_config_backup(&bytes, "wrong", BackupPlatform::Macos),
            Err(ConfigBackupError::DecryptionFailed)
        );
        let mut tampered = envelope(&bytes);
        let mut ciphertext = STANDARD.decode(&tampered.ciphertext).unwrap();
        ciphertext[0] ^= 1;
        tampered.ciphertext = STANDARD.encode(ciphertext);
        assert_eq!(
            parse_config_backup(&encode(tampered), "password", BackupPlatform::Macos),
            Err(ConfigBackupError::DecryptionFailed)
        );
        let mut tag_tampered = envelope(&bytes);
        let mut ciphertext = STANDARD.decode(&tag_tampered.ciphertext).unwrap();
        let last = ciphertext.len() - 1;
        ciphertext[last] ^= 1;
        tag_tampered.ciphertext = STANDARD.encode(ciphertext);
        assert_eq!(
            parse_config_backup(&encode(tag_tampered), "password", BackupPlatform::Macos),
            Err(ConfigBackupError::DecryptionFailed)
        );
    }

    #[test]
    fn rejects_empty_password_and_non_backup_or_truncated_input() {
        assert_eq!(
            export_config_backup(input(), ""),
            Err(ConfigBackupError::EmptyPassword)
        );
        assert_eq!(
            parse_config_backup(b"random", "password", BackupPlatform::Macos),
            Err(ConfigBackupError::NotFluxBackup)
        );
        assert_eq!(
            parse_config_backup(&exported()[..10], "password", BackupPlatform::Macos),
            Err(ConfigBackupError::NotFluxBackup)
        );
    }

    #[test]
    fn rejects_unsupported_version_platform_and_invalid_crypto_metadata() {
        let bytes = exported();
        let mut newer = envelope(&bytes);
        newer.version = 2;
        assert_eq!(
            parse_config_backup(&encode(newer), "password", BackupPlatform::Macos),
            Err(ConfigBackupError::UnsupportedVersion)
        );
        assert_eq!(
            parse_config_backup(&bytes, "password", BackupPlatform::Ios),
            Err(ConfigBackupError::PlatformMismatch)
        );
        let mut wrong_magic = envelope(&bytes);
        wrong_magic.magic = "NOT_FLUX".into();
        assert_eq!(
            parse_config_backup(&encode(wrong_magic), "password", BackupPlatform::Macos),
            Err(ConfigBackupError::NotFluxBackup)
        );
        let mut malformed = envelope(&bytes);
        malformed.kdf.memory_kib = 999_999;
        assert_eq!(
            parse_config_backup(&encode(malformed), "password", BackupPlatform::Macos),
            Err(ConfigBackupError::InvalidCryptoMetadata)
        );
        let mut bad_nonce = envelope(&bytes);
        bad_nonce.nonce = STANDARD.encode([0u8; 2]);
        assert_eq!(
            parse_config_backup(&encode(bad_nonce), "password", BackupPlatform::Macos),
            Err(ConfigBackupError::InvalidCryptoMetadata)
        );
        let mut bad_salt = envelope(&bytes);
        bad_salt.salt = STANDARD.encode([0u8; 2]);
        assert_eq!(
            parse_config_backup(&encode(bad_salt), "password", BackupPlatform::Macos),
            Err(ConfigBackupError::InvalidCryptoMetadata)
        );
    }

    #[test]
    fn rejects_invalid_decrypted_contents() {
        let bytes = exported();
        for edit in [
            Box::new(|payload: &mut Value| payload["account"]["api_key"] = json!(""))
                as Box<dyn FnOnce(&mut Value)>,
            Box::new(|payload: &mut Value| {
                payload["account"]["installation_base"] = json!("not a URL")
            }),
            Box::new(|payload: &mut Value| {
                payload["core_settings"]["detail_character_limit"] = json!(123)
            }),
            Box::new(|payload: &mut Value| {
                let duplicate = payload["feed_preferences"][0].clone();
                payload["feed_preferences"]
                    .as_array_mut()
                    .unwrap()
                    .push(duplicate)
            }),
            Box::new(|payload: &mut Value| {
                payload["platform_settings"]["data"] = json!("not an object")
            }),
        ] {
            assert_eq!(
                parse_config_backup(
                    &rewrite_payload(&bytes, edit),
                    "password",
                    BackupPlatform::Macos
                ),
                Err(ConfigBackupError::InvalidContents)
            );
        }
    }

    #[test]
    fn rejects_oversized_input_before_parsing() {
        assert_eq!(
            parse_config_backup(
                &vec![b'x'; MAX_BACKUP_BYTES + 1],
                "password",
                BackupPlatform::Macos
            ),
            Err(ConfigBackupError::InputTooLarge)
        );
    }
}

#[cfg(not(test))]
fn production_kdf() -> KdfMetadata {
    KdfMetadata {
        algorithm: "argon2id".into(),
        memory_kib: PRODUCTION_MEMORY_KIB,
        iterations: PRODUCTION_ITERATIONS,
        parallelism: PRODUCTION_PARALLELISM,
    }
}
