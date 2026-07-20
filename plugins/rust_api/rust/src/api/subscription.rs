use flutter_rust_bridge::frb;

/// Resolves Happ/V2RayTun/INCY wrappers and decrypts recognized encrypted links.
#[frb]
pub fn resolve_subscription_input(input: String) -> Result<String, String> {
    let unwrapped = hpwnr::unwrap_link(&input);
    hpwnr::decrypt_link(&unwrapped)
        .map(|decrypted| decrypted.unwrap_or(unwrapped))
        .map_err(|error| format!("Failed to decrypt subscription link: {error}"))
}

/// Removes Happ's optional AES-GCM response layer while leaving plain responses unchanged.
#[frb]
pub fn decrypt_subscription_response(
    url: String,
    body: Vec<u8>,
    encrypt_tag: Option<String>,
) -> Result<Vec<u8>, String> {
    let Some(tag) = encrypt_tag
        .as_deref()
        .map(str::trim)
        .filter(|tag| !tag.is_empty())
    else {
        return Ok(body);
    };
    let Some(key_name) = response_key_name(&url) else {
        return Ok(body);
    };
    if !is_supported_response_key(key_name) {
        return Err(format!(
            "Unsupported subscription encryption key: {key_name}"
        ));
    }

    let original = body.clone();
    let decrypted = hpwnr::decrypt_response_body(&url, body, Some(tag));
    if decrypted == original {
        return Err("Failed to decrypt encrypted subscription response".to_string());
    }
    Ok(decrypted)
}

fn response_key_name(url: &str) -> Option<&str> {
    let query = url.split_once('?')?.1.split('#').next().unwrap_or_default();
    query.split('&').find_map(|pair| {
        let (name, value) = pair.split_once('=').unwrap_or((pair, ""));
        (name == "key" && !value.is_empty()).then_some(value)
    })
}

fn is_supported_response_key(key: &str) -> bool {
    matches!(
        key,
        "key01"
            | "key02"
            | "key03"
            | "key04"
            | "key05"
            | "key06"
            | "key07"
            | "key08"
            | "key09"
            | "key10"
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use hpwnr::{encrypt_happ, HappMode};

    #[test]
    fn resolves_wrapped_happ_links() {
        let encrypted = encrypt_happ(HappMode::Crypt3, "https://example.com/sub").unwrap();
        let wrapped = format!("happ://add/{encrypted}");

        assert_eq!(
            resolve_subscription_input(wrapped).unwrap(),
            "https://example.com/sub"
        );
    }

    #[test]
    fn leaves_plain_responses_unchanged() {
        let body = b"proxies: []".to_vec();

        assert_eq!(
            decrypt_subscription_response("https://example.com/sub".into(), body.clone(), None)
                .unwrap(),
            body
        );
    }

    #[test]
    fn rejects_invalid_encrypted_responses() {
        let result = decrypt_subscription_response(
            "https://example.com/sub?key=key01".into(),
            b"invalid".to_vec(),
            Some("invalid".into()),
        );

        assert!(result.is_err());
    }
}
