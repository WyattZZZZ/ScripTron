use crate::types::{ContentBlock, HermesError, Message, ToolDefinition};
use async_trait::async_trait;
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

#[derive(Debug, Clone, PartialEq)]
pub struct ModelResponse {
    pub content: Vec<ContentBlock>,
    pub stop_reason: String,
}

impl ModelResponse {
    pub fn text(text: impl Into<String>) -> Self {
        Self {
            content: vec![ContentBlock::Text { text: text.into() }],
            stop_reason: "end_turn".into(),
        }
    }
}

#[async_trait]
pub trait ModelProvider: Send + Sync {
    async fn complete(
        &self,
        system: &str,
        messages: &[Message],
        tools: &[ToolDefinition],
        max_tokens: u32,
    ) -> Result<ModelResponse, HermesError>;
}

#[derive(Debug, Clone, Default)]
pub struct MockProvider {
    responses: Arc<Mutex<VecDeque<Result<ModelResponse, String>>>>,
    calls: Arc<Mutex<Vec<MockProviderCall>>>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct MockProviderCall {
    pub system: String,
    pub messages: Vec<Message>,
    pub tools: Vec<ToolDefinition>,
    pub max_tokens: u32,
}

impl MockProvider {
    pub fn new(responses: impl IntoIterator<Item = ModelResponse>) -> Self {
        Self {
            responses: Arc::new(Mutex::new(
                responses.into_iter().map(Ok).collect::<VecDeque<_>>(),
            )),
            calls: Arc::new(Mutex::new(Vec::new())),
        }
    }

    pub fn with_error(error: impl Into<String>) -> Self {
        Self {
            responses: Arc::new(Mutex::new(VecDeque::from([Err(error.into())]))),
            calls: Arc::new(Mutex::new(Vec::new())),
        }
    }

    pub fn calls(&self) -> Vec<MockProviderCall> {
        self.calls.lock().expect("mock calls poisoned").clone()
    }
}

#[async_trait]
impl ModelProvider for MockProvider {
    async fn complete(
        &self,
        system: &str,
        messages: &[Message],
        tools: &[ToolDefinition],
        max_tokens: u32,
    ) -> Result<ModelResponse, HermesError> {
        self.calls
            .lock()
            .expect("mock calls poisoned")
            .push(MockProviderCall {
                system: system.into(),
                messages: messages.to_vec(),
                tools: tools.to_vec(),
                max_tokens,
            });

        self.responses
            .lock()
            .expect("mock responses poisoned")
            .pop_front()
            .unwrap_or_else(|| Ok(ModelResponse::text("")))
            .map_err(HermesError::Model)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn mock_provider_records_calls() {
        let provider = MockProvider::new([ModelResponse::text("hello")]);

        let response = provider
            .complete(
                "system",
                &[Message::user_text("hi")],
                &[ToolDefinition {
                    name: "noop".into(),
                    description: "No-op".into(),
                    input_schema: serde_json::json!({"type": "object"}),
                }],
                64,
            )
            .await
            .unwrap();

        assert_eq!(response, ModelResponse::text("hello"));
        let calls = provider.calls();
        assert_eq!(calls.len(), 1);
        assert_eq!(calls[0].system, "system");
        assert_eq!(calls[0].messages[0].role, "user");
        assert_eq!(calls[0].tools[0].name, "noop");
    }
}
