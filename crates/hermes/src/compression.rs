use crate::types::{ContentBlock, Message};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CompressionPolicy {
    pub max_chars: usize,
    pub keep_recent_messages: usize,
}

impl Default for CompressionPolicy {
    fn default() -> Self {
        Self {
            max_chars: 48_000,
            keep_recent_messages: 8,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum CompressionDecision {
    Keep,
    Compress {
        summary: String,
        retained: Vec<Message>,
    },
}

impl CompressionPolicy {
    pub fn evaluate(&self, messages: &[Message]) -> CompressionDecision {
        let total_chars = messages
            .iter()
            .flat_map(|message| message.content.iter())
            .filter_map(content_block_text)
            .map(char_count)
            .sum::<usize>();

        if total_chars <= self.max_chars {
            return CompressionDecision::Keep;
        }

        let retained_start = messages.len().saturating_sub(self.keep_recent_messages);
        let retained = messages[retained_start..].to_vec();
        let summary = format!(
            "Earlier conversation compressed by Hermes: {} messages, approximately {} text chars.",
            retained_start, total_chars
        );
        CompressionDecision::Compress { summary, retained }
    }

    pub fn should_compress_text(&self, text: &str) -> bool {
        char_count(text) > self.max_chars
    }

    pub fn compress_text_if_needed(&self, label: &str, text: &str) -> CompressedText {
        let original_chars = char_count(text);
        if original_chars <= self.max_chars {
            return CompressedText {
                text: text.to_string(),
                original_chars,
                max_chars: self.max_chars,
                compressed: false,
            };
        }

        CompressedText {
            text: placeholder_summary(label, text, original_chars, self.max_chars),
            original_chars,
            max_chars: self.max_chars,
            compressed: true,
        }
    }
}

fn content_block_text(block: &ContentBlock) -> Option<&str> {
    match block {
        ContentBlock::Text { text } => Some(text),
        _ => None,
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CompressedText {
    pub text: String,
    pub original_chars: usize,
    pub max_chars: usize,
    pub compressed: bool,
}

pub fn char_count(text: &str) -> usize {
    text.chars().count()
}

fn placeholder_summary(label: &str, text: &str, original_chars: usize, max_chars: usize) -> String {
    if max_chars == 0 {
        return String::new();
    }

    let header = format!(
        "[summary placeholder: {}; original_chars={}; max_chars={}]\n",
        label.trim(),
        original_chars,
        max_chars
    );
    if char_count(&header) >= max_chars {
        return take_chars(&header, max_chars);
    }

    let remaining = max_chars - char_count(&header);
    let marker = "\n...\n";
    let body = if remaining > char_count(marker) {
        let body_budget = remaining - char_count(marker);
        let head_budget = (body_budget + 1) / 2;
        let tail_budget = body_budget / 2;
        format!(
            "{}{}{}",
            take_chars(text, head_budget),
            marker,
            take_last_chars(text, tail_budget)
        )
    } else {
        take_chars(text, remaining)
    };

    take_chars(&format!("{header}{body}"), max_chars)
}

fn take_chars(text: &str, count: usize) -> String {
    text.chars().take(count).collect()
}

fn take_last_chars(text: &str, count: usize) -> String {
    let mut chars = text.chars().rev().take(count).collect::<Vec<_>>();
    chars.reverse();
    chars.into_iter().collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::Message;

    #[test]
    fn keeps_messages_below_budget() {
        let policy = CompressionPolicy {
            max_chars: 10,
            keep_recent_messages: 1,
        };

        assert_eq!(
            policy.evaluate(&[Message::user_text("short")]),
            CompressionDecision::Keep
        );
    }

    #[test]
    fn compresses_messages_above_budget() {
        let policy = CompressionPolicy {
            max_chars: 5,
            keep_recent_messages: 1,
        };

        let decision =
            policy.evaluate(&[Message::user_text("first"), Message::user_text("second")]);

        match decision {
            CompressionDecision::Compress { summary, retained } => {
                assert!(summary.contains("1 messages"));
                assert_eq!(retained, vec![Message::user_text("second")]);
            }
            CompressionDecision::Keep => panic!("expected compression"),
        }
    }

    #[test]
    fn text_budget_uses_character_count() {
        let policy = CompressionPolicy {
            max_chars: 4,
            keep_recent_messages: 1,
        };

        assert!(!policy.should_compress_text("你好ab"));
        assert!(policy.should_compress_text("你好abc"));
    }

    #[test]
    fn text_compression_returns_placeholder_within_budget() {
        let policy = CompressionPolicy {
            max_chars: 80,
            keep_recent_messages: 1,
        };
        let compressed = policy.compress_text_if_needed(
            "memory",
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz",
        );

        assert!(compressed.compressed);
        assert!(char_count(&compressed.text) <= policy.max_chars);
        assert!(compressed.text.contains("summary placeholder"));
    }
}
