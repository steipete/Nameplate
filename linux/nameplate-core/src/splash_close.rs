//! Which overlay windows a connect splash is allowed to close.
//!
//! Splash and attention are separate layers. A monitor change, an unlock,
//! or an explicit splash must not dismiss an attention card.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OverlayRole {
    Splash,
    Attention,
}

/// A splash closes earlier splash windows only. Attention stays up.
pub fn splash_closes(role: OverlayRole) -> bool {
    matches!(role, OverlayRole::Splash)
}

/// Open splash and attention layers. Splash may replace itself only.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct OverlayPresence {
    pub splash: bool,
    pub attention: bool,
}

impl OverlayPresence {
    pub fn show_splash(&mut self) {
        if splash_closes(OverlayRole::Splash) {
            self.splash = false;
        }
        self.splash = true;
        if splash_closes(OverlayRole::Attention) {
            self.attention = false;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splash_leaves_an_unclicked_attention_card_open() {
        let mut presence = OverlayPresence {
            splash: false,
            attention: true,
        };
        presence.show_splash();
        assert!(
            presence.attention,
            "splash dismissed an attention card the user has not clicked"
        );
        assert!(presence.splash);
    }

    #[test]
    fn splash_replaces_only_the_previous_splash() {
        let mut presence = OverlayPresence {
            splash: true,
            attention: false,
        };
        presence.show_splash();
        assert!(presence.splash);
        assert!(!presence.attention);
    }
}
